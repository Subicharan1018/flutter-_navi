import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/play_event.dart';
import '../models/song.dart';

const Duration _kSessionTimeout = Duration(minutes: 30);

class ListeningEventCollector {
  final AppDatabase _db;

  PlayEvent? _openEvent;
  Song? _currentSong;
  int _currentRepeatCount = 0;

  String _sessionId = _generateUuid();
  DateTime _lastPlayTime = DateTime(1970);

  // RC-7 FIX: Re-entrancy guard to prevent orphaned PlayEvent rows
  // when rapid track changes call onSongStarted before the previous
  // call finishes processing.
  bool _isProcessing = false;

  ListeningEventCollector(this._db);

  void onSongStarted({
    required Song song,
    required String sourceContext,
    required String transitionType,
    Song? prevSong,
    Duration positionAtSwitch = Duration.zero,
    int queuePosition = 0,
    bool shuffleActive = false,
  }) {
    // RC-7: Skip if already processing a song transition.
    if (_isProcessing) return;
    _isProcessing = true;
    try {
    if (_currentSong?.id == song.id && _openEvent != null) {
      debugPrint('[Analytics] ⚠ Self-transition for "${song.title}" — ignoring');
      return;
    }

    PlayEvent? closedEvent;
    final Song? effectivePrev = prevSong ?? _currentSong;
    if (_openEvent != null && effectivePrev != null) {
      closedEvent = _closeEvent(effectivePrev, positionAtSwitch, _currentRepeatCount);
    }
    _currentRepeatCount = 0;

    final now = DateTime.now();
    final gap = now.difference(_lastPlayTime);
    if (gap > _kSessionTimeout) {
      _sessionId = _generateUuid();
      debugPrint('[Analytics] 🔑 New session (gap ${gap.inMinutes}min) → $_sessionId');
    }
    _lastPlayTime = now;

    _openEvent = PlayEvent.open(
      playId: _generateUuid(),
      songId: song.id,
      sessionId: _sessionId,
      sourceContext: sourceContext,
      queuePosition: queuePosition,
      shuffleActive: shuffleActive,
    );

    if (effectivePrev != null && closedEvent != null) {
      if (!closedEvent.skipBeforeEnd) {
        _recordPair(
          prevSongId: effectivePrev.id,
          currentSongId: song.id,
          transitionType: transitionType,
        );
      }
    }

    _currentSong = song;
    _upsertSongMetadata(song);
    } finally {
      _isProcessing = false;
    }
  }

  void onSongEnded(Song song, Duration playedDuration) {
    if (_openEvent == null || _openEvent!.songId != song.id) return;
    _closeEvent(song, playedDuration, _currentRepeatCount);
    _currentRepeatCount = 0;
  }

  void onSongRepeated() {
    _currentRepeatCount++;
  }

  void recordSuggestFeedback(Song song, bool isMore) {
    final label = isMore ? 'suggest_more' : 'suggest_less';
    _db.into(_db.userFeedback).insert(UserFeedbackCompanion.insert(
      songId: song.id,
      feedbackType: label,
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: _sessionId,
    )).catchError((e) {
      debugPrint('[Analytics] ❌ recordSuggestFeedback error: $e');
      return 0;
    });
  }

  void persistWeight(String songId, double weight) {
    _db.into(_db.songWeights).insertOnConflictUpdate(SongWeightsCompanion.insert(
      songId: songId,
      weight: Value(weight),
    )).catchError((e) {
      debugPrint('[Analytics] ❌ persistWeight error: $e');
      return 0;
    });
  }

  Future<Map<String, double>> loadWeights() async {
    try {
      final rows = await _db.select(_db.songWeights).get();
      return {for (final r in rows) r.songId: r.weight};
    } catch (e) {
      debugPrint('[Analytics] ❌ loadWeights error: $e');
      return {};
    }
  }

  Future<AnalyticsStats> getStats() async {
    try {
      final playCount = await _db.playEvents.count().getSingle();
      final songCount = await _db.songMetadata.count().getSingle();
      final pairCount = await _db.songPairs.count().getSingle();
      final feedbackCount = await _db.userFeedback.count().getSingle();

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

  Future<Map<String, String>> exportCsv() async { return {}; }
  Future<Map<String, List<Map<String, dynamic>>>> exportJson() async { return {}; }

  Future<void> deleteDataOlderThan(DateTime threshold) async {
    final ts = threshold.millisecondsSinceEpoch;
    await (_db.delete(_db.playEvents)..where((t) => t.tsStart.isSmallerThanValue(ts))).go();
  }

  Future<List<String>> exportCsvToDownloads() async { return []; }

  PlayEvent? _closeEvent(Song song, Duration playedDuration, int repeats) {
    final event = _openEvent;
    if (event == null) return null;
    event.close(playedDuration, song.duration, repeats: repeats);
    _openEvent = null;
    _writeEvent(event);
    return event;
  }

  void _writeEvent(PlayEvent event) {
    _db.into(_db.playEvents).insertOnConflictUpdate(PlayEventsCompanion.insert(
      playId: event.playId,
      songId: event.songId,
      sessionId: event.sessionId,
      tsStart: event.timestampStart.millisecondsSinceEpoch,
      tsEnd: Value(event.timestampEnd?.millisecondsSinceEpoch),
      playDurSec: Value(event.playDurationSec),
      skipBefore50: Value(event.skipBeforeEnd),
      skipPositionPct: Value(event.skipPositionPct),
      repeatCount: Value(event.repeatCount),
      queuePosition: Value(event.queuePosition),
      shuffleActive: Value(event.shuffleActive),
      sourceContext: event.sourceContext,
      hourOfDay: event.hourOfDay,
      dayOfWeek: event.dayOfWeek,
    )).catchError((e) {
      debugPrint('[Analytics] ❌ writeEvent error: $e');
      return 0;
    });
  }

  void _upsertSongMetadata(Song song) {
    _db.into(_db.songMetadata).insertOnConflictUpdate(SongMetadataCompanion.insert(
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
      updatedAt: DateTime.now().millisecondsSinceEpoch,
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
    _db.customStatement('''
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
    ]).catchError((e) {
      debugPrint('[Analytics] ❌ recordPair error: $e');
    });
  }

  static final Random _random = Random.secure();
  static String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<void> dispose() async {
    if (_openEvent != null && _currentSong != null) {
      _closeEvent(_currentSong!, Duration(seconds: _openEvent!.playDurationSec), _currentRepeatCount);
    }
  }
}

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
