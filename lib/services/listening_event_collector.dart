import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';
import '../models/play_event.dart';
import '../models/song.dart';

const Duration _kSessionTimeout = Duration(minutes: 30);

/// Minimum play duration (seconds) before an event is persisted.
const double _kMinPlayDurationSec = 2.0;

/// Minimum play duration (seconds) before a song-pair is recorded.
const double _kMinPairDurationSec = 5.0;

// ── CSV helpers ───────────────────────────────────────────────────────────────

/// Wraps a field value for safe CSV embedding.
/// null  → empty string
/// bool  → "true" / "false"
/// other → toString(), double-quoted if it contains commas, quotes, or newlines.
String _csvField(dynamic value) {
  if (value == null) return '';
  final s = value is bool ? value.toString() : value.toString();
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Builds a CSV string from [headers] and [rows].
/// Column order matches [headers] exactly.
String _buildCsv(List<String> headers, List<Map<String, dynamic>> rows) {
  final buf = StringBuffer();
  buf.writeln(headers.join(','));
  for (final row in rows) {
    buf.writeln(headers.map((h) => _csvField(row[h])).join(','));
  }
  return buf.toString();
}

/// Writes [content] to [filePath], creating parent dirs as needed.
Future<File> _writeFile(String filePath, String content) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsString(content, flush: true);
  return file;
}

// ─────────────────────────────────────────────────────────────────────────────

class ListeningEventCollector {
  final AppDatabase _db;
  final DateTime Function() _now;

  PlayEvent? _openEvent;
  Song? _currentSong;
  int _currentRepeatCount = 0;

  String _sessionId = _generateUuid();
  DateTime _lastPlayTime = DateTime(1970);

  // Sequence-based re-entrancy guard.
  int _processingSeq = 0;

  // Rapid-fire duplicate fingerprint.
  String? _lastStartFingerprint;
  DateTime _lastStartTime = DateTime(1970);

  ListeningEventCollector(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  // ──────────────────────────────────────────────────────────────────────────
  // Core event lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  void onSongStarted({
    required Song song,
    required String sourceContext,
    required String transitionType,
    Song? prevSong,
    Duration positionAtSwitch = Duration.zero,
    int queuePosition = 0,
    bool shuffleActive = false,
  }) {
    final mySeq = ++_processingSeq;

    // Collapse rapid duplicate calls for the same song within 500 ms.
    final now = _now();
    final fingerprint = '${song.id}@$queuePosition';
    if (fingerprint == _lastStartFingerprint &&
        now.difference(_lastStartTime).inMilliseconds < 500) {
      debugPrint(
        '[Analytics] ⏭ Rapid duplicate for "${song.title}" — collapsed',
      );
      return;
    }

    // Ignore self-transitions (same song + same queue slot already open).
    if (_currentSong?.id == song.id &&
        _openEvent != null &&
        _openEvent!.queuePosition == queuePosition &&
        _openEvent!.songId == song.id) {
      debugPrint(
        '[Analytics] ⏭ Self-transition for "${song.title}" — ignoring',
      );
      return;
    }

    _lastStartFingerprint = fingerprint;
    _lastStartTime = now;

    // Close previous event with the position snapshot already captured by
    // the player (before _lastKnownPosition was zeroed).
    PlayEvent? closedEvent;
    final Song? effectivePrev = prevSong ?? _currentSong;
    if (_openEvent != null && effectivePrev != null) {
      closedEvent = _closeEvent(
        effectivePrev,
        positionAtSwitch,
        _currentRepeatCount,
      );
    }
    _currentRepeatCount = 0;

    // Session boundary.
    final gap = now.difference(_lastPlayTime);
    if (gap > _kSessionTimeout) {
      _sessionId = _generateUuid();
      debugPrint(
        '[Analytics] 🔑 New session (gap ${gap.inMinutes}min) → $_sessionId',
      );
    }
    _lastPlayTime = _now();

    // Abort if superseded by a newer call arriving during the above work.
    if (mySeq != _processingSeq) {
      debugPrint(
        '[Analytics] ⏭ Superseded — aborting start for "${song.title}"',
      );
      return;
    }

    _openEvent = PlayEvent.open(
      playId: _generateUuid(),
      songId: song.id,
      sessionId: _sessionId,
      sourceContext: sourceContext,
      queuePosition: queuePosition,
      shuffleActive: shuffleActive,
    );

    debugPrint(
      '[Analytics] ⏺ Started: "${song.title}" '
      '(ctx=$sourceContext, q=$queuePosition, shuffle=$shuffleActive)',
    );

    // Record co-play pair only when the previous play was substantial.
    if (effectivePrev != null &&
        closedEvent != null &&
        closedEvent.playDurationSec >= _kMinPairDurationSec &&
        !closedEvent.skipBeforeEnd) {
      _recordPair(
        prevSongId: effectivePrev.id,
        currentSongId: song.id,
        transitionType: transitionType,
      );
    }

    _currentSong = song;
    _upsertSongMetadata(song);
  }

  void onSongEnded(Song song, Duration playedDuration) {
    if (_openEvent == null || _openEvent!.songId != song.id) return;
    _closeEvent(song, playedDuration, _currentRepeatCount);
    _currentRepeatCount = 0;
  }

  void onSongRepeated() => _currentRepeatCount++;

  void recordSuggestFeedback(Song song, bool isMore) {
    _db
        .into(_db.userFeedback)
        .insert(
          UserFeedbackCompanion.insert(
            songId: song.id,
            feedbackType: isMore ? 'suggest_more' : 'suggest_less',
            ts: DateTime.now().millisecondsSinceEpoch,
            sessionId: _sessionId,
          ),
        )
        .catchError((e) {
          debugPrint('[Analytics] ❌ recordSuggestFeedback: $e');
          return 0;
        });
  }

  void persistWeight(String songId, double weight) {
    _db
        .into(_db.songWeights)
        .insertOnConflictUpdate(
          SongWeightsCompanion.insert(songId: songId, weight: Value(weight)),
        )
        .catchError((e) {
          debugPrint('[Analytics] ❌ persistWeight: $e');
          return 0;
        });
  }

  Future<Map<String, double>> loadWeights() async {
    try {
      final rows = await _db.select(_db.songWeights).get();
      return {for (final r in rows) r.songId: r.weight};
    } catch (e) {
      debugPrint('[Analytics] ❌ loadWeights: $e');
      return {};
    }
  }

  Future<AnalyticsStats> getStats() async {
    try {
      return AnalyticsStats(
        playEvents: await _db.playEvents.count().getSingle(),
        uniqueSongs: await _db.songMetadata.count().getSingle(),
        songPairs: await _db.songPairs.count().getSingle(),
        feedbackActions: await _db.userFeedback.count().getSingle(),
      );
    } catch (_) {
      return const AnalyticsStats(
        playEvents: 0,
        uniqueSongs: 0,
        songPairs: 0,
        feedbackActions: 0,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Export — CSV
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns { filename → csv_string } for all four tables.
  /// Use this when you want to handle file I/O yourself (e.g. share sheet).
  Future<Map<String, String>> exportCsv() async {
    try {
      return {
        'play_events.csv': await _buildPlayEventsCsv(),
        'song_metadata.csv': await _buildSongMetadataCsv(),
        'song_pairs.csv': await _buildSongPairsCsv(),
        'user_feedback.csv': await _buildUserFeedbackCsv(),
      };
    } catch (e) {
      debugPrint('[Analytics] ❌ exportCsv: $e');
      return {};
    }
  }

  /// Writes all four CSVs to the best available export directory and returns
  /// the list of absolute paths that were written.
  ///
  /// Android — tries the public Downloads folder first; falls back to the
  ///           app-scoped external storage directory if that isn't writable.
  /// iOS     — writes to the app's Documents directory, which is exposed in
  ///           the Files app when UIFileSharingEnabled = YES in Info.plist.
  Future<List<String>> exportCsvToDownloads() async {
    final dir = await _resolveExportDirectory();
    final timestamp = _fileTimestamp();
    final csvMap = await exportCsv();

    if (csvMap.isEmpty) {
      debugPrint('[Analytics] ⚠ exportCsvToDownloads: nothing to export');
      return [];
    }

    final paths = <String>[];
    for (final entry in csvMap.entries) {
      // e.g. "play_events_20250502_143022.csv"
      final stem = entry.key.replaceAll('.csv', '');
      final filename = '${stem}_$timestamp.csv';
      final file = await _writeFile('${dir.path}/$filename', entry.value);
      paths.add(file.path);
      debugPrint(
        '[Analytics] 📁 ${file.path} '
        '(${(entry.value.length / 1024).toStringAsFixed(1)} KB, '
        '${entry.value.split('\n').length - 1} rows)',
      );
    }
    return paths;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Export — JSON
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns { table_name → list_of_row_maps } for all four tables.
  Future<Map<String, List<Map<String, dynamic>>>> exportJson() async {
    try {
      return {
        'play_events': await _fetchPlayEventsRaw(),
        'song_metadata': await _fetchSongMetadataRaw(),
        'song_pairs': await _fetchSongPairsRaw(),
        'user_feedback': await _fetchUserFeedbackRaw(),
      };
    } catch (e) {
      debugPrint('[Analytics] ❌ exportJson: $e');
      return {};
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Maintenance
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> deleteDataOlderThan(DateTime threshold) async {
    final ts = threshold.millisecondsSinceEpoch;
    await (_db.delete(
      _db.playEvents,
    )..where((t) => t.tsStart.isSmallerThanValue(ts))).go();
  }

  /// Purges noise events: sub-threshold duration AND marked as skipped.
  Future<int> purgeNoiseEvents() async {
    return (_db.delete(_db.playEvents)..where(
          (t) =>
              t.playDurSec.isSmallerThanValue(_kMinPlayDurationSec.toInt()) &
              t.skipBefore50.equals(true),
        ))
        .go();
  }

  Future<void> dispose() async {
    if (_openEvent != null && _currentSong != null) {
      // At dispose time the position stream is gone — use wall-clock elapsed.
      final elapsed = _now().difference(_openEvent!.timestampStart);
      _closeEvent(_currentSong!, elapsed, _currentRepeatCount);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private — event internals
  // ──────────────────────────────────────────────────────────────────────────

  /// Closes [_openEvent] and persists it if the duration passes the threshold.
  /// Returns the event (persisted or not) so the caller can inspect it.
  PlayEvent? _closeEvent(Song song, Duration playedDuration, int repeats) {
    final event = _openEvent;
    if (event == null) return null;

    // Prefer the position-stream value; fall back to wall-clock elapsed when
    // positionAtSwitch is Duration.zero (stream stall, app suspend, dispose).
    final wallClock = _now().difference(event.timestampStart);
    final effectiveDuration =
        (playedDuration == Duration.zero && wallClock > Duration.zero)
        ? wallClock
        : playedDuration;

    event.close(effectiveDuration, song.duration, repeats: repeats);
    _openEvent = null;

    if (event.playDurationSec < _kMinPlayDurationSec) {
      debugPrint(
        '[Analytics] 🗑 Discarded short event: "${song.title}" '
        '(${event.playDurationSec.toStringAsFixed(1)}s < ${_kMinPlayDurationSec}s)',
      );
      return event;
    }

    _writeEvent(event);
    debugPrint(
      '[Analytics] ✅ Persisted: "${song.title}" '
      '(${event.playDurationSec.toStringAsFixed(1)}s, '
      'skip=${event.skipBeforeEnd}, repeats=${event.repeatCount})',
    );
    return event;
  }

  void _writeEvent(PlayEvent event) {
    _db
        .into(_db.playEvents)
        .insertOnConflictUpdate(
          PlayEventsCompanion.insert(
            playId: event.playId,
            songId: event.songId,
            sessionId: event.sessionId,
            tsStart: event.timestampStart.millisecondsSinceEpoch,
            tsEnd: Value(event.timestampEnd?.millisecondsSinceEpoch),
            // PlayEvent.playDurationSec is a double (sub-second precision kept in
            // the model); the Drift column is IntColumn so we floor here.
            playDurSec: Value(event.playDurationSec.toInt()),
            skipBefore50: Value(event.skipBeforeEnd),
            skipPositionPct: Value(event.skipPositionPct),
            repeatCount: Value(event.repeatCount),
            queuePosition: Value(event.queuePosition),
            shuffleActive: Value(event.shuffleActive),
            sourceContext: event.sourceContext,
            hourOfDay: event.hourOfDay,
            dayOfWeek: event.dayOfWeek,
          ),
        )
        .catchError((e) {
          debugPrint('[Analytics] ❌ writeEvent: $e');
          return 0;
        });
  }

  void _upsertSongMetadata(Song song) {
    _db
        .into(_db.songMetadata)
        .insertOnConflictUpdate(
          SongMetadataCompanion.insert(
            songId: song.id,
            trackName: song.title,
            artistName: song.artist,
            albumName: song.album,
            genre: Value(song.genre.isEmpty ? null : song.genre),
            composer: Value(song.composer.isEmpty ? null : song.composer),
            durationSec: song.duration,
            year: Value(song.year > 0 ? song.year : null),
            playCount: Value(song.playCount),
            rating: Value(song.rating),
            starred: Value(song.starred),
            updatedAt: _now().millisecondsSinceEpoch,
          ),
        )
        .catchError((e) {
          debugPrint('[Analytics] ❌ upsertSongMetadata: $e');
          return 0;
        });
  }

  void _recordPair({
    required String prevSongId,
    required String currentSongId,
    required String transitionType,
  }) {
    _db
        .customStatement(
          '''
      INSERT INTO song_pairs (prev_song_id, current_song_id, transition_type,
                              play_count, last_seen)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(prev_song_id, current_song_id, transition_type)
      DO UPDATE SET
        play_count = play_count + 1,
        last_seen  = excluded.last_seen
    ''',
          [
            prevSongId,
            currentSongId,
            transitionType,
            _now().millisecondsSinceEpoch,
          ],
        )
        .catchError((e) {
          debugPrint('[Analytics] ❌ recordPair: $e');
        });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private — raw data fetchers
  // Shared by both CSV and JSON exporters so there is one source of truth
  // for column/field names.
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchPlayEventsRaw() async {
    final rows = await _db.select(_db.playEvents).get();
    return rows
        .map(
          (r) => <String, dynamic>{
            'play_id': r.playId,
            'song_id': r.songId,
            'session_id': r.sessionId,
            'ts_start': r.tsStart,
            'ts_end': r.tsEnd,
            'play_dur_sec': r.playDurSec,
            'skip_before_50': r.skipBefore50,
            'skip_position_pct': r.skipPositionPct,
            'repeat_count': r.repeatCount,
            'queue_position': r.queuePosition,
            'shuffle_active': r.shuffleActive,
            'source_context': r.sourceContext,
            'hour_of_day': r.hourOfDay,
            'day_of_week': r.dayOfWeek,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchSongMetadataRaw() async {
    final rows = await _db.select(_db.songMetadata).get();
    return rows
        .map(
          (r) => <String, dynamic>{
            'song_id': r.songId,
            'track_name': r.trackName,
            'artist_name': r.artistName,
            'album_name': r.albumName,
            'genre': r.genre,
            'composer': r.composer,
            'duration_sec': r.durationSec,
            'year': r.year,
            'play_count': r.playCount,
            'rating': r.rating,
            'starred': r.starred,
            'updated_at': r.updatedAt,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchSongPairsRaw() async {
    final rows = await _db.select(_db.songPairs).get();
    return rows
        .map(
          (r) => <String, dynamic>{
            'prev_song_id': r.prevSongId,
            'current_song_id': r.currentSongId,
            'transition_type': r.transitionType,
            'play_count': r.playCount,
            'last_seen': r.lastSeen,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchUserFeedbackRaw() async {
    final rows = await _db.select(_db.userFeedback).get();
    return rows
        .map(
          (r) => <String, dynamic>{
            'id': r.id,
            'song_id': r.songId,
            'feedback_type': r.feedbackType,
            'ts': r.ts,
            'session_id': r.sessionId,
          },
        )
        .toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private — CSV builders
  // Column order is declared explicitly here so the output is stable even if
  // the raw-fetcher maps are reordered.
  // ──────────────────────────────────────────────────────────────────────────

  Future<String> _buildPlayEventsCsv() async {
    const headers = [
      'play_id',
      'song_id',
      'session_id',
      'ts_start',
      'ts_end',
      'play_dur_sec',
      'skip_before_50',
      'skip_position_pct',
      'repeat_count',
      'queue_position',
      'shuffle_active',
      'source_context',
      'hour_of_day',
      'day_of_week',
    ];
    return _buildCsv(headers, await _fetchPlayEventsRaw());
  }

  Future<String> _buildSongMetadataCsv() async {
    const headers = [
      'song_id',
      'track_name',
      'artist_name',
      'album_name',
      'genre',
      'composer',
      'duration_sec',
      'year',
      'play_count',
      'rating',
      'starred',
      'updated_at',
    ];
    return _buildCsv(headers, await _fetchSongMetadataRaw());
  }

  Future<String> _buildSongPairsCsv() async {
    const headers = [
      'prev_song_id',
      'current_song_id',
      'transition_type',
      'play_count',
      'last_seen',
    ];
    return _buildCsv(headers, await _fetchSongPairsRaw());
  }

  Future<String> _buildUserFeedbackCsv() async {
    const headers = ['id', 'song_id', 'feedback_type', 'ts', 'session_id'];
    return _buildCsv(headers, await _fetchUserFeedbackRaw());
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private — filesystem helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the best writable export directory for the current platform.
  Future<Directory> _resolveExportDirectory() async {
    if (Platform.isAndroid) {
      // Prefer the well-known public Downloads path.
      final pub = Directory('/storage/emulated/0/Download');
      if (await pub.exists()) {
        try {
          // Probe write access — avoid crashing on a permission exception later.
          final probe = File('${pub.path}/.probe_${_generateUuid()}');
          await probe.create();
          await probe.delete();
          return pub;
        } catch (_) {
          // No WRITE_EXTERNAL_STORAGE — fall through.
        }
      }
      // Fall back to the app-scoped external directory.  Still visible in
      // Android's file manager under "Android/data/<package>/files/Downloads".
      final ext = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (ext != null && ext.isNotEmpty) return ext.first;
    }

    // iOS: Documents is exposed via Files app (UIFileSharingEnabled).
    // All other platforms: standard documents directory.
    return getApplicationDocumentsDirectory();
  }

  /// Returns a timestamp string safe for filenames, e.g. "20250502_143022".
  String _fileTimestamp() {
    final n = DateTime.now();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(n.year, 4)}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}${p(n.second)}';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UUID
  // ──────────────────────────────────────────────────────────────────────────

  static final Random _random = Random.secure();
  static String _generateUuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-'
        '${h.substring(20, 32)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
