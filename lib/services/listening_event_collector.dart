import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/play_event.dart';
import '../models/song.dart';

// ---------------------------------------------------------------------------
// ListeningEventCollector
//
// Silently records every play event, song metadata snapshot, and song-to-song
// transition to a dedicated SQLite database (navivibe_analytics.db).
//
// Design rules:
//   • All DB writes are fire-and-forget (unawaited) — never blocks the UI.
//   • The database file is separate from navivibe_cache.db so a cache wipe
//     never touches analytics data.
//   • Only attributes available from Navidrome/Subsonic are persisted;
//     audio features (BPM, energy, valence …) are not collected.
//   • mood_tag is stored as NULL; future ML inference will fill it in.
// ---------------------------------------------------------------------------

// Session timeout: a new session UUID is generated if the gap between the
// last play and the current play exceeds this duration.
const Duration _kSessionTimeout = Duration(minutes: 30);

class ListeningEventCollector {
  static const _kDbName = 'navivibe_analytics.db';
  static const _kVersion = 1;

  Database? _db;

  // ── In-flight state ────────────────────────────────────────────────────────

  /// The play_event row that has been opened but not yet closed.
  PlayEvent? _openEvent;

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
  void onSongStarted({
    required Song song,
    required String sourceContext,
    required String transitionType,
    Song? prevSong,
    Duration positionAtSwitch = Duration.zero,
  }) {
    // Close any open event for the previous song first.
    if (_openEvent != null && prevSong != null) {
      _closeEvent(prevSong, positionAtSwitch);
    }

    // ── Session management ──────────────────────────────────────────────────
    final now = DateTime.now();
    if (now.difference(_lastPlayTime) > _kSessionTimeout) {
      _sessionId = _generateUuid();
    }
    _lastPlayTime = now;

    // ── Open new event ──────────────────────────────────────────────────────
    _openEvent = PlayEvent.open(
      playId: _generateUuid(),
      songId: song.id,
      sessionId: _sessionId,
      sourceContext: sourceContext,
    );

    // ── Pair recording ──────────────────────────────────────────────────────
    if (prevSong != null) {
      _recordPair(
        prevSongId: prevSong.id,
        currentSongId: song.id,
        transitionType: transitionType,
      );
    }

    // ── Metadata upsert (fire-and-forget) ───────────────────────────────────
    _upsertSongMetadata(song);
  }

  /// Call this when a song ends naturally or the app is backgrounded/closed.
  ///
  /// [song]          — the song that was playing.
  /// [playedDuration] — how far through the track playback reached.
  void onSongEnded(Song song, Duration playedDuration) {
    if (_openEvent == null || _openEvent!.songId != song.id) return;
    _closeEvent(song, playedDuration);
  }

  /// Returns summary statistics for the Settings screen.
  /// Returns zero counts gracefully if the database has not been opened yet.
  Future<AnalyticsStats> getStats() async {
    try {
      final db = await _open();
      final playCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM play_events')) ??
          0;
      final songCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM song_metadata')) ??
          0;
      final pairCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM song_pairs')) ??
          0;
      return AnalyticsStats(
          playEvents: playCount,
          uniqueSongs: songCount,
          songPairs: pairCount);
    } catch (_) {
      return const AnalyticsStats(playEvents: 0, uniqueSongs: 0, songPairs: 0);
    }
  }

  /// Exports all three analytics tables as CSV strings.
  /// Returns a map of { tableName → csvString }.
  Future<Map<String, String>> exportCsv() async {
    final db = await _open();
    final result = <String, String>{};

    // play_events
    final events = await db.query('play_events', orderBy: 'ts_start ASC');
    result['play_events'] = _toCsv(events);

    // song_metadata
    final meta = await db.query('song_metadata', orderBy: 'track_name ASC');
    result['song_metadata'] = _toCsv(meta);

    // song_pairs
    final pairs =
        await db.query('song_pairs', orderBy: 'play_count DESC');
    result['song_pairs'] = _toCsv(pairs);

    return result;
  }

  /// Writes CSV files to the device's external storage Downloads folder.
  /// Returns the list of paths written.
  Future<List<String>> exportCsvToDownloads() async {
    final csvMap = await exportCsv();
    final paths = <String>[];

    // On Android the public Downloads folder is /storage/emulated/0/Download.
    // On other platforms we fall back to a temp directory.
    final String baseDir;
    if (Platform.isAndroid) {
      baseDir = '/storage/emulated/0/Download';
    } else {
      baseDir = (await getDatabasesPath()).replaceAll('databases', '');
    }

    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

    for (final entry in csvMap.entries) {
      final path = p.join(baseDir, 'navivibe_${entry.key}_$timestamp.csv');
      await File(path).writeAsString(entry.value);
      paths.add(path);
    }

    return paths;
  }

  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _closeEvent(Song song, Duration playedDuration) {
    final event = _openEvent;
    if (event == null) return;
    event.close(playedDuration, song.duration);
    _openEvent = null;
    _writeEvent(event); // fire-and-forget
  }

  void _writeEvent(PlayEvent event) {
    _open().then((db) => db.insert(
      'play_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    )).catchError((e) {
      debugPrint('[Collector] writeEvent error: $e');
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
        'play_count': song.playCount,
        'rating': song.rating,
        'starred': song.starred ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      // Always update metadata so rating/starred/playCount stay current.
      conflictAlgorithm: ConflictAlgorithm.replace,
    )).catchError((e) {
      debugPrint('[Collector] upsertSongMetadata error: $e');
    });
  }

  void _recordPair({
    required String prevSongId,
    required String currentSongId,
    required String transitionType,
  }) {
    _open().then((db) async {
      // INSERT … ON CONFLICT → increment play_count.
      await db.rawInsert('''
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
      ]);
    }).catchError((e) {
      debugPrint('[Collector] recordPair error: $e');
    });
  }

  // ---------------------------------------------------------------------------
  // Database initialisation
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _kDbName);
    _db = await openDatabase(
      dbPath,
      version: _kVersion,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE play_events (
        play_id        TEXT PRIMARY KEY,
        song_id        TEXT NOT NULL,
        session_id     TEXT NOT NULL,
        ts_start       INTEGER NOT NULL,
        ts_end         INTEGER,
        play_dur_sec   INTEGER NOT NULL DEFAULT 0,
        skip_before_50 INTEGER NOT NULL DEFAULT 0,
        source_context TEXT NOT NULL,
        hour_of_day    INTEGER NOT NULL,
        day_of_week    INTEGER NOT NULL,
        is_weekend     INTEGER NOT NULL,
        mood_tag       TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE song_metadata (
        song_id      TEXT PRIMARY KEY,
        track_name   TEXT NOT NULL,
        artist_name  TEXT NOT NULL,
        album_name   TEXT NOT NULL,
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

    // pair_strength = play_count * 1.0 / SUM(play_count WHERE prev_song_id = X)
    // Computed at query time — not stored.
    await db.execute('''
      CREATE TABLE song_pairs (
        prev_song_id    TEXT NOT NULL,
        current_song_id TEXT NOT NULL,
        transition_type TEXT NOT NULL,
        play_count      INTEGER NOT NULL DEFAULT 1,
        last_seen       INTEGER NOT NULL,
        PRIMARY KEY (prev_song_id, current_song_id, transition_type)
      )
    ''');

    // Indexes for the most common query patterns.
    await db.execute(
        'CREATE INDEX idx_events_song ON play_events (song_id)');
    await db.execute(
        'CREATE INDEX idx_events_session ON play_events (session_id)');
    await db.execute(
        'CREATE INDEX idx_pairs_prev ON song_pairs (prev_song_id)');
  }

  // ---------------------------------------------------------------------------
  // UUID v4 generator (no external package needed — uses dart:math)
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
        // Wrap in quotes if it contains a comma, quote, or newline.
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

  const AnalyticsStats({
    required this.playEvents,
    required this.uniqueSongs,
    required this.songPairs,
  });
}
