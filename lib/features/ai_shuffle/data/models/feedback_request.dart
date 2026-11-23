// =============================================================================
// FeedbackRequest — payload for POST /feedback (play-event schema_version 2)
// =============================================================================
//
// One class for every event the app reports about listening: a play that
// finished (complete / skip / replay), one that started, a seek, or a queue
// edit. Field list: docs/play-event-schema.md. Servers that predate v2 ignore
// the fields they do not know; the server accepts the old shape too.

import 'package:flutter/foundation.dart';

import '../../../play_outbox/logic/play_event.dart';

/// Immutable model representing a single POST /feedback request body.
class FeedbackRequest {
  final String title;
  final String filePath;
  final String genreBucket;
  final String composer;
  final double listenRatio;
  final String endReason;
  final int durationS;
  final String sessionId;
  final int sessionDepth;
  final String genreStreakType;
  final int genreStreakCount;
  final double volume;

  /// Kept so old call sites compile; no longer sent (the server stamps weather).
  @Deprecated('The server stamps weather itself; this value is ignored.')
  final int weatherCode;
  @Deprecated('The server stamps weather itself; this value is ignored.')
  final double temperatureC;

  /// Identifies this play so a retried delivery is counted once. Servers that
  /// predate the field ignore it.
  final String? playId;

  /// When the play started (epoch ms), for a play delivered late. Servers
  /// that predate the field stamp it on receipt instead.
  final int? playedAtMs;

  // ── schema_version 2 ────────────────────────────────────────────────────────
  final PlayEventType? eventType;

  /// Seconds the listener really heard (not position, not wall clock).
  final double? secondsPlayed;

  /// The phone's UTC offset in minutes when the play started (IST = 330).
  final int? tzOffsetMin;
  final PlaySource? playSource;

  /// Where the server put this song in the batch it served, and how it scored.
  final int? slot;
  final double? score;
  final String? servedBy;
  final String? servedId;

  /// True for the 5 % of smart-shuffle slots placed without the AI.
  final bool? holdout;
  final String? clientVersion;
  final String? platform;

  /// For start / seek events: the play they belong to. (For these events
  /// [playId] is the event's own id, which the outbox needs to be different.)
  final String? parentPlayId;

  /// For [PlayEventType.queueEdit]: what was done and where.
  final QueueEditKind? queueEditKind;
  final int? fromIndex;
  final int? toIndex;

  /// For [PlayEventType.seek]: where the scrub started and ended.
  final int? seekFromMs;
  final int? seekToMs;

  const FeedbackRequest({
    required this.title,
    required this.listenRatio,
    required this.endReason,
    this.durationS = 0,
    this.filePath = '',
    this.genreBucket = '',
    this.composer = '',
    this.sessionId = '',
    this.sessionDepth = 0,
    this.genreStreakType = '',
    this.genreStreakCount = 0,
    this.volume = 1.0,
    @Deprecated('ignored') this.weatherCode = 800,
    @Deprecated('ignored') this.temperatureC = 25.0,
    this.playId,
    this.playedAtMs,
    this.eventType,
    this.secondsPlayed,
    this.tzOffsetMin,
    this.playSource,
    this.slot,
    this.score,
    this.servedBy,
    this.servedId,
    this.holdout,
    this.clientVersion,
    this.platform,
    this.parentPlayId,
    this.queueEditKind,
    this.fromIndex,
    this.toIndex,
    this.seekFromMs,
    this.seekToMs,
  }) : assert(title.length > 0, 'FeedbackRequest.title must not be empty'),
       assert(
         listenRatio >= 0.0 && listenRatio <= 1.01,
         'FeedbackRequest.listenRatio out of range: $listenRatio',
       ),
       assert(
         kReleaseMode || genreBucket.length > 0,
         'FeedbackRequest.genreBucket is empty — check Song.genre mapping or FLAC tag',
       ),
       assert(
         kReleaseMode || composer.length > 0,
         'FeedbackRequest.composer is empty — check Song.composer mapping or FLAC tag',
       );

  /// Start, seek and queue-edit events (everything that is not a finished play).
  bool get isAuxEvent => eventType != null && !eventType!.isFinish;

  /// Weather is no longer sent: the server stamps its own reading. (The old app
  /// sent 800 / 25.0 for every play, which is why 97 % of old rows carry it.)
  Map<String, dynamic> toJson() => {
    'schema_version': kPlayEventSchemaVersion,
    'title': title,
    'file_path': filePath,
    'genre_bucket': genreBucket,
    'composer': composer,
    'listen_ratio': listenRatio,
    'end_reason': endReason,
    'duration_s': durationS,
    'session_id': sessionId,
    'session_depth': sessionDepth,
    'genre_streak_type': genreStreakType,
    'genre_streak_count': genreStreakCount,
    'volume': volume,
    // A finish event's idempotency key is `play_id`; every other event has its own
    // `event_id` and points at its play with `play_id`.
    if (playId != null) (isAuxEvent ? 'event_id' : 'play_id'): playId,
    if (isAuxEvent && parentPlayId != null) 'play_id': parentPlayId,
    if (playedAtMs != null) 'played_at': playedAtMs,
    if (eventType != null) 'event_type': eventType!.wire,
    if (secondsPlayed != null) 'seconds_played': double.parse(secondsPlayed!.toStringAsFixed(2)),
    if (tzOffsetMin != null) 'tz_offset_min': tzOffsetMin,
    if (playSource != null) 'play_source': playSource!.wire,
    if (slot != null) 'slot': slot,
    if (score != null) 'score': score,
    if (servedBy != null) 'served_by': servedBy,
    if (servedId != null) 'served_id': servedId,
    if (holdout != null) 'holdout': holdout,
    if (clientVersion != null && clientVersion!.isNotEmpty) 'client_version': clientVersion,
    if (platform != null) 'platform': platform,
    if (queueEditKind != null)
      'queue_edit': {
        'kind': queueEditKind!.wire,
        if (fromIndex != null) 'from_index': fromIndex,
        if (toIndex != null) 'to_index': toIndex,
      },
    if (seekFromMs != null) 'from_ms': seekFromMs,
    if (seekToMs != null) 'to_ms': seekToMs,
  };

  /// This request stamped with the play it belongs to.
  FeedbackRequest withPlay({required String playId, required int playedAtMs}) =>
      copyWith(playId: playId, playedAtMs: playedAtMs);

  FeedbackRequest copyWith({
    String? playId,
    int? playedAtMs,
    PlayEventType? eventType,
    double? secondsPlayed,
    int? tzOffsetMin,
    PlaySource? playSource,
    int? slot,
    double? score,
    String? servedBy,
    String? servedId,
    bool? holdout,
    String? clientVersion,
    String? platform,
  }) =>
      FeedbackRequest(
        title: title,
        filePath: filePath,
        genreBucket: genreBucket,
        composer: composer,
        listenRatio: listenRatio,
        endReason: endReason,
        durationS: durationS,
        sessionId: sessionId,
        sessionDepth: sessionDepth,
        genreStreakType: genreStreakType,
        genreStreakCount: genreStreakCount,
        volume: volume,
        playId: playId ?? this.playId,
        playedAtMs: playedAtMs ?? this.playedAtMs,
        eventType: eventType ?? this.eventType,
        secondsPlayed: secondsPlayed ?? this.secondsPlayed,
        tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
        playSource: playSource ?? this.playSource,
        slot: slot ?? this.slot,
        score: score ?? this.score,
        servedBy: servedBy ?? this.servedBy,
        servedId: servedId ?? this.servedId,
        holdout: holdout ?? this.holdout,
        clientVersion: clientVersion ?? this.clientVersion,
        platform: platform ?? this.platform,
        parentPlayId: parentPlayId,
        queueEditKind: queueEditKind,
        fromIndex: fromIndex,
        toIndex: toIndex,
        seekFromMs: seekFromMs,
        seekToMs: seekToMs,
      );

  /// Reads back what [toJson] wrote (the outbox stores requests as JSON).
  factory FeedbackRequest.fromJson(Map<String, dynamic> j) {
    final qe = j['queue_edit'];
    final type = PlayEventType.values.where((t) => t.wire == j['event_type']).firstOrNull;
    final aux = type != null && !type.isFinish;
    return FeedbackRequest(
      title: j['title'] as String,
      filePath: (j['file_path'] as String?) ?? '',
      genreBucket: (j['genre_bucket'] as String?) ?? 'unknown',
      composer: (j['composer'] as String?) ?? 'unknown',
      listenRatio: ((j['listen_ratio'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      endReason: (j['end_reason'] as String?) ?? 'natural',
      durationS: (j['duration_s'] as num?)?.toInt() ?? 0,
      sessionId: (j['session_id'] as String?) ?? '',
      sessionDepth: (j['session_depth'] as num?)?.toInt() ?? 0,
      genreStreakType: (j['genre_streak_type'] as String?) ?? '',
      genreStreakCount: (j['genre_streak_count'] as num?)?.toInt() ?? 0,
      volume: ((j['volume'] as num?) ?? 1).toDouble(),
      playId: (aux ? j['event_id'] : j['play_id']) as String?,
      playedAtMs: (j['played_at'] as num?)?.toInt(),
      eventType: type,
      secondsPlayed: (j['seconds_played'] as num?)?.toDouble(),
      tzOffsetMin: (j['tz_offset_min'] as num?)?.toInt(),
      playSource: PlaySource.values.where((s) => s.wire == j['play_source']).firstOrNull,
      slot: (j['slot'] as num?)?.toInt(),
      score: (j['score'] as num?)?.toDouble(),
      servedBy: j['served_by'] as String?,
      servedId: j['served_id'] as String?,
      holdout: j['holdout'] as bool?,
      clientVersion: j['client_version'] as String?,
      platform: j['platform'] as String?,
      parentPlayId: aux ? j['play_id'] as String? : null,
      queueEditKind: qe is Map ? QueueEditKind.values.where((k) => k.wire == qe['kind']).firstOrNull : null,
      fromIndex: qe is Map ? (qe['from_index'] as num?)?.toInt() : null,
      toIndex: qe is Map ? (qe['to_index'] as num?)?.toInt() : null,
      seekFromMs: (j['from_ms'] as num?)?.toInt(),
      seekToMs: (j['to_ms'] as num?)?.toInt(),
    );
  }
}
