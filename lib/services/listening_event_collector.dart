import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/play_event.dart';
import '../models/song.dart';

// ---------------------------------------------------------------------------
// ListeningEventCollector  (schema v3)
//
// Changes vs v2:
//   • play_events:  added skip_position_pct, repeat_count, queue_position,
//                   shuffle_active; removed is_weekend, mood_tag.
//   • song_weights: new table persisting per-song dynamicWeight across restarts.
//   • song_metadata: play_count / rating / starred kept in sync with the
//                    server values pushed in from PlayerNotifier on every
//                    song start (so the table never goes stale).
//
// Design rules (unchanged):
//   • All DB writes are fire-and-forget (unawaited) — never blocks the UI.
//   • DB is separate from navivibe_cache.db so a cache wipe can't touch it.
// ---------------------------------------------------------------------------

const Duration _kSessionTimeout = Duration(minutes: 30);

class ListeningEventCollector {
  static const _kDbName = 'navivibe_analytics.db';
  static const _kVersion = 3; // v3: new play_events schema + song_weights

  Database? _db;

  // ── In-flight state ────────────────────────────────────────────────────────

  PlayEvent? _openEvent;

  /// The Song object currently playing — kept for orphan-event recovery.
  Song? _currentSong;

  // ── Loop tracking ──────────────────────────────────────────────────────────
  // Incremented by PlayerNotifier when LoopMode.one restarts the track.
  int _currentRepeatCount = 0;

  // ── Session tracking ───────────────────────────────────────────────────────

  String _sessionId = _generateUuid();
  DateTime _lastPlayTime = DateTime(1970);

  // ---------------------------------------------------------------------------
  // Public API — called by PlayerNotifier
  // ---------------------------------------------------------------------------

  /// Call this immediately when a new song starts playing.
  ///
  /// [song]           — the incoming song.
  /// [sourceContext]  — 'user_queue' | 'playlist' | 'search' | 'autoplay' |
  ///                    'manual_next' | 'user_selected'
  /// [transitionType] — 'autoplay' | 'manual_next' | 'user_selected'
  /// [prevSong]       — the song that was playing before (null on first play).
  /// [positionAtSwitch] — position of [prevSong] at the moment of switch.
  /// [queuePosition]  — zero-based index of the NEW song in the current queue.
  /// [shuffleActive]  — whether shuffle was active when the new song started.
  void onSongStarted({
    required Song song,
    required String sourceContext,
    required String transitionType,
    Song? prevSong,
    Duration positionAtSwitch = Duration.zero,
    int queuePosition = 0,
    bool shuffleActive = false,
  }) {
    // ── Guard: self-transition (same song fired twice) ────────────────────────
    if (_currentSong?.id == song.id && _openEvent != null) {
      debugPrint(
          '[Analytics] ⚠ Self-transition for "${song.title}" — ignoring');
      return;
    }

    // ── Close any open event ─────────────────────────────────────────────────
    PlayEvent? closedEvent;
    final Song? effectivePrev = prevSong ?? _currentSong;
    if (_openEvent != null && effectivePrev != null) {
      debugPrint('[Analytics] ⏹ Song ending: "${effectivePrev.title}" '
          'at ${positionAtSwitch.inSeconds}s '
          'repeats=$_currentRepeatCount');
      closedEvent =
          _closeEvent(effectivePrev, positionAtSwitch, _currentRepeatCount);
    } else if (_openEvent != null) {
      debugPrint(
          '[Analytics] ⚠ Orphaned open event with no song reference — discarding');
      _openEvent = null;
    }
    _currentRepeatCount = 0;

    // ── Session management ────────────────────────────────────────────────────
    final now = DateTime.now();
    final gap = now.difference(_lastPlayTime);
    if (gap > _kSessionTimeout) {
      _sessionId = _generateUuid();
      debugPrint('[Analytics] 🔑 New session (gap ${gap.inMinutes}min) → $_sessionId');
    }
    _lastPlayTime = now;

    // ── Open new event ────────────────────────────────────────────────────────
    _openEvent = PlayEvent.open(
      playId: _generateUuid(),
      songId: song.id,
      sessionId: _sessionId,
      sourceContext: sourceContext,
      queuePosition: queuePosition,
      shuffleActive: shuffleActive,
    );
    debugPrint('[Analytics] ▶ Opened play_event for "${song.title}" '
        '(id=${song.id}) source=$sourceContext pos=$queuePosition '
        'shuffle=$shuffleActive hour=${_openEvent!.hourOfDay}');

    // ── Pair recording ────────────────────────────────────────────────────────
    if (effectivePrev != null && closedEvent != null) {
      if (closedEvent.skipBeforeEnd) {
        debugPrint('[Analytics] ⏭ Pair skipped: "${effectivePrev.title}" '
            'skipped at ${((closedEvent.skipPositionPct ?? 0) * 100).round()}%');
      } else {
        _recordPair(
          prevSongId: effectivePrev.id,
          currentSongId: song.id,
          transitionType: transitionType,
        );
      }
    }

    _currentSong = song;

    // ── Metadata upsert (fire-and-forget) ─────────────────────────────────────
    _upsertSongMetadata(song);
  }

  /// Call when a song ends naturally or the app is backgrounded/closed.
  void onSongEnded(Song song, Duration playedDuration) {
    if (_openEvent == null || _openEvent!.songId != song.id) {
      debugPrint('[Analytics] ⚠ onSongEnded: no matching open event '
          '(song=${song.id}, open=${_openEvent?.songId})');
      return;
    }
    debugPrint(
        '[Analytics] ⏹ onSongEnded: "${song.title}" at ${playedDuration.inSeconds}s');
    _closeEvent(song, playedDuration, _currentRepeatCount);
    _currentRepeatCount = 0;
  }

  /// Call each time the user loops the current song (LoopMode.one fires).
  void onSongRepeated() {
    _currentRepeatCount++;
    debugPrint('[Analytics] 🔁 Repeat #$_currentRepeatCount '
        'for "${_currentSong?.title}"');
  }

  /// Records an explicit Suggest More / Suggest Less action.
  void recordSuggestFeedback(Song song, bool isMore) {
    final label = isMore ? 'suggest_more' : 'suggest_less';
    debugPrint('[Analytics] 👍 Feedback "$label" for "${song.title}"');
    _open().then((db) => db.insert(
          'user_feedback',
          {
            'song_id': song.id,
            'feedback_type': label,
            'ts': DateTime.now().millisecondsSinceEpoch,
            'session_id': _sessionId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        )).then((_) {
      debugPrint('[Analytics] ✅ user_feedback written for "${song.title}"');
    }).catchError((e) {
      debugPrint('[Analytics] ❌ recordSuggestFeedback error: $e');
    });
  }

  // ---------------------------------------------------------------------------
  // Dynamic weight persistence
  // ---------------------------------------------------------------------------

  /// Persists the updated dynamic weight for [songId].
  /// Fire-and-forget — called from AudioHandler.updateSongWeight.
  void persistWeight(String songId, double weight) {
    _open().then((db) async {
      await db.insert(
        'song_weights',
        {'song_id': songId, 'weight': weight},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }).catchError((Object e) {
      debugPrint('[Analytics] ❌ persistWeight error: $e');
    });
  }

  /// Loads all persisted weights as a map {songId → weight}.
  /// Called once during startup to restore weights into the audio handler.
  Future<Map<String, double>> loadWeights() async {
    try {
      final db = await _open();
      final rows = await db.query('song_weights');
      return {for (final r in rows) r['song_id'] as String: (r['weight'] as num).toDouble()};
    } catch (e) {
      debugPrint('[Analytics] ❌ loadWeights error: $e');
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  Future<AnalyticsStats> getStats() async {
    try {
      final db = await _open();
      final playCount =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM play_events')) ?? 0;
      final songCount =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM song_metadata')) ?? 0;
      final pairCount =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM song_pairs')) ?? 0;
      final feedbackCount =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM user_feedback')) ?? 0;
      return AnalyticsStats(
          playEvents: playCount,
          uniqueSongs: songCount,
          songPairs: pairCount,
          feedbackActions: feedbackCount);
    } catch (_) {
      return const AnalyticsStats(
          playEvents: 0, uniqueSongs: 0, songPairs: 0, feedbackActions: 0);
    }
  }

  // ---------------------------------------------------------------------------
  // CSV export
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> exportCsv() async {
    final db = await _open();
    return {
      'play_events': _toCsv(await db.query('play_events', orderBy: 'ts_start ASC')),
      'song_metadata': _toCsv(await db.query('song_metadata', orderBy: 'track_name ASC')),
      'song_pairs': _toCsv(await db.query('song_pairs', orderBy: 'play_count DESC')),
      'user_feedback': _toCsv(await db.query('user_feedback', orderBy: 'ts ASC')),
      'song_weights': _toCsv(await db.query('song_weights', orderBy: 'weight DESC')),
    };
  }

  Future<Map<String, List<Map<String, dynamic>>>> exportJson() async {
    final db = await _open();
    return {
      'play_events': await db.query('play_events', orderBy: 'ts_start ASC'),
      'song_metadata': await db.query('song_metadata', orderBy: 'track_name ASC'),
      'song_pairs': await db.query('song_pairs', orderBy: 'play_count DESC'),
      'user_feedback': await db.query('user_feedback', orderBy: 'ts ASC'),
      'song_weights': await db.query('song_weights', orderBy: 'weight DESC'),
    };
  }

  Future<void> deleteDataOlderThan(DateTime threshold) async {
    final db = await _open();
    final ts = threshold.millisecondsSinceEpoch;
    await db.delete('play_events', where: 'ts_start < ?', whereArgs: [ts]);
    // Optional: could delete old song_pairs or user_feedback if desired, 
    // but play_events is the main storage hog.
    debugPrint('[Analytics] 🧹 Deleted play_events older than $threshold');
  }

  Future<List<String>> exportCsvToDownloads() async {
    debugPrint('[Analytics] 📤 Starting CSV export...');
    final csvMap = await exportCsv();
    final paths = <String>[];

    final String baseDir = Platform.isAndroid
        ? '/storage/emulated/0/Download'
        : (await getDatabasesPath()).replaceAll('databases', '');

    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

    for (final entry in csvMap.entries) {
      final path = p.join(baseDir, 'navivibe_${entry.key}_$timestamp.csv');
      await File(path).writeAsString(entry.value);
      debugPrint('[Analytics] 📄 Exported ${entry.key}: $path '
          '(${entry.value.split("\n").length - 1} rows)');
      paths.add(path);
    }

    debugPrint('[Analytics] ✅ Export complete: ${paths.length} files');
    return paths;
  }

  Future<void> dispose() async {
    if (_openEvent != null && _currentSong != null) {
      debugPrint(
          '[Analytics] 💾 Flushing open event on dispose for "${_currentSong!.title}"');
      _closeEvent(
          _currentSong!, Duration(seconds: _openEvent!.playDurationSec), _currentRepeatCount);
    }
    await _db?.close();
    _db = null;
    _currentSong = null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  PlayEvent? _closeEvent(Song song, Duration playedDuration, int repeats) {
    final event = _openEvent;
    if (event == null) return null;
    event.close(playedDuration, song.duration, repeats: repeats);
    _openEvent = null;
    debugPrint('[Analytics] 💾 Closing play_event: "${song.title}" '
        'played=${event.playDurationSec}s / ${song.duration}s '
        'skipped=${event.skipBeforeEnd} '
        'skipPct=${event.skipPositionPct?.toStringAsFixed(2) ?? "n/a"} '
        'repeats=${event.repeatCount}');
    _writeEvent(event);
    return event;
  }

  void _writeEvent(PlayEvent event) {
    _open().then((db) async {
      final rowId = await db.insert(
        'play_events',
        event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[Analytics] ✅ play_event written (rowId=$rowId '
          'song=${event.songId} dur=${event.playDurationSec}s)');
    }).catchError((Object e) {
      debugPrint('[Analytics] ❌ writeEvent error: $e');
    });
  }

  void _upsertSongMetadata(Song song) {
    _open().then((db) => db.insert(
          'song_metadata',
          {
            'song_id': song.id,
            'track_name': song.title,
            'artist_name': song.artist,
            'album_name': song.album,
            'genre': song.genre.isEmpty ? null : song.genre,
            'composer': song.composer.isEmpty ? null : song.composer,
            'duration_sec': song.duration,
            'year': song.year > 0 ? song.year : null,
            // Always refresh from server values passed in via Song object.
            'play_count': song.playCount,
            'rating': song.rating,
            'starred': song.starred ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).catchError((e) {
      debugPrint('[Analytics] ❌ upsertSongMetadata error: $e');
      return 0;
    });
  }

  void _recordPair({
    required String prevSongId,
    required String currentSongId,
    required String transitionType,
  }) {
    _open()
        .then((db) => db.rawInsert('''
      INSERT INTO song_pairs (prev_song_id, current_song_id, transition_type,
                              play_count, last_seen)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(prev_song_id, current_song_id, transition_type)
      DO UPDATE SET
        play_count = play_count + 1,
        last_seen  = excluded.last_seen
    ''', [
          prevSongId,
          currentSongId,
          transitionType,
          DateTime.now().millisecondsSinceEpoch,
        ]))
        .catchError((e) {
      debugPrint('[Analytics] ❌ recordPair error: $e');
      return 0;
    });
  }

  // ---------------------------------------------------------------------------
  // Database initialisation (v3)
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _kDbName);
    debugPrint('[Analytics] 📂 Opening analytics DB at: $dbPath');
    _db = await openDatabase(
      dbPath,
      version: _kVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    debugPrint('[Analytics] ✅ Analytics DB ready');
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[Analytics] ⬆ Migrating DB v$oldVersion → v$newVersion');

    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_feedback (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          song_id     TEXT NOT NULL,
          feedback_type TEXT NOT NULL,
          ts          INTEGER NOT NULL,
          session_id  TEXT NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_feedback_song ON user_feedback (song_id)');
    }

    if (oldVersion < 3) {
      // Add new columns to play_events (SQLite allows ADD COLUMN only).
      await _safeAddColumn(db, 'play_events', 'skip_position_pct', 'REAL');
      await _safeAddColumn(db, 'play_events', 'repeat_count', 'INTEGER NOT NULL DEFAULT 0');
      await _safeAddColumn(db, 'play_events', 'queue_position', 'INTEGER NOT NULL DEFAULT 0');
      await _safeAddColumn(db, 'play_events', 'shuffle_active', 'INTEGER NOT NULL DEFAULT 0');

      // New table for dynamic weights.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS song_weights (
          song_id TEXT PRIMARY KEY,
          weight  REAL  NOT NULL DEFAULT 1.0
        )
      ''');
    }
  }

  Future<void> _safeAddColumn(
      Database db, String table, String column, String type) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    } catch (_) {
      // Column already exists — ignore.
    }
  }

  Future<void> _createAllTables(Database db) async {
    // play_events (v3 schema)
    await db.execute('''
      CREATE TABLE play_events (
        play_id          TEXT    PRIMARY KEY,
        song_id          TEXT    NOT NULL,
        session_id       TEXT    NOT NULL,
        ts_start         INTEGER NOT NULL,
        ts_end           INTEGER,
        play_dur_sec     INTEGER NOT NULL DEFAULT 0,
        skip_before_50   INTEGER NOT NULL DEFAULT 0,
        skip_position_pct REAL,
        repeat_count     INTEGER NOT NULL DEFAULT 0,
        queue_position   INTEGER NOT NULL DEFAULT 0,
        shuffle_active   INTEGER NOT NULL DEFAULT 0,
        source_context   TEXT    NOT NULL,
        hour_of_day      INTEGER NOT NULL,
        day_of_week      INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE song_metadata (
        song_id      TEXT    PRIMARY KEY,
        track_name   TEXT    NOT NULL,
        artist_name  TEXT    NOT NULL,
        album_name   TEXT    NOT NULL,
        genre        TEXT,
        composer     TEXT,
        duration_sec INTEGER NOT NULL,
        year         INTEGER,
        play_count   INTEGER NOT NULL DEFAULT 0,
        rating       INTEGER NOT NULL DEFAULT 0,
        starred      INTEGER NOT NULL DEFAULT 0,
        updated_at   INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE song_pairs (
        prev_song_id    TEXT    NOT NULL,
        current_song_id TEXT    NOT NULL,
        transition_type TEXT    NOT NULL,
        play_count      INTEGER NOT NULL DEFAULT 1,
        last_seen       INTEGER NOT NULL,
        PRIMARY KEY (prev_song_id, current_song_id, transition_type)
      )
    ''');

    await db.execute('''
      CREATE TABLE user_feedback (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id       TEXT    NOT NULL,
        feedback_type TEXT    NOT NULL,
        ts            INTEGER NOT NULL,
        session_id    TEXT    NOT NULL
      )
    ''');

    /// Persists per-song dynamicWeight across app restarts.
    await db.execute('''
      CREATE TABLE song_weights (
        song_id TEXT PRIMARY KEY,
        weight  REAL NOT NULL DEFAULT 1.0
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_events_song    ON play_events (song_id)');
    await db.execute('CREATE INDEX idx_events_session ON play_events (session_id)');
    await db.execute('CREATE INDEX idx_events_hour    ON play_events (hour_of_day)');
    await db.execute('CREATE INDEX idx_pairs_prev     ON song_pairs  (prev_song_id)');
    await db.execute('CREATE INDEX idx_feedback_song  ON user_feedback (song_id)');
  }

  // ---------------------------------------------------------------------------
  // UUID v4 generator
  // ---------------------------------------------------------------------------

  static final Random _random = Random.secure();

  static String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  // ---------------------------------------------------------------------------
  // CSV serialisation
  // ---------------------------------------------------------------------------

  static String _toCsv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    final header = rows.first.keys.join(',');
    final lines = rows.map((row) {
      return row.values.map((v) {
        if (v == null) return '';
        final s = v.toString();
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }).join(',');
    }).toList();
    return '$header\n${lines.join('\n')}';
  }
}

// ---------------------------------------------------------------------------
// Simple stats DTO for the Settings screen
// ---------------------------------------------------------------------------

class AnalyticsStats {
  final int playEvents;
  final int uniqueSongs;
  final int songPairs;
  final int feedbackActions;

  const AnalyticsStats({
    required this.playEvents,
    required this.uniqueSongs,
    required this.songPairs,
    required this.feedbackActions,
  });
}
