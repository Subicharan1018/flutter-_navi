// =============================================================================
// FeedbackRequest — payload for POST /feedback (v4.0.0)
// =============================================================================

import 'package:flutter/foundation.dart';

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
  final int weatherCode;
  final double temperatureC;
  final double volume;

  /// Identifies this play so a retried delivery is counted once. Servers that
  /// predate the field ignore it.
  final String? playId;

  /// When the play started (epoch ms), for a play delivered late. Servers
  /// that predate the field stamp it on receipt instead.
  final int? playedAtMs;

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
    this.weatherCode = 800,
    this.temperatureC = 25.0,
    this.volume = 1.0,
    this.playId,
    this.playedAtMs,
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

  Map<String, dynamic> toJson() => {
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
    'weather_code': weatherCode,
    'temperature_c': temperatureC,
    'volume': volume,
    if (playId != null) 'play_id': playId,
    if (playedAtMs != null) 'played_at': playedAtMs,
  };

  /// This request stamped with the play it belongs to.
  FeedbackRequest withPlay({required String playId, required int playedAtMs}) =>
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
        weatherCode: weatherCode,
        temperatureC: temperatureC,
        volume: volume,
        playId: playId,
        playedAtMs: playedAtMs,
      );

  /// Reads back what [toJson] wrote (the outbox stores requests as JSON).
  factory FeedbackRequest.fromJson(Map<String, dynamic> j) => FeedbackRequest(
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
        weatherCode: (j['weather_code'] as num?)?.toInt() ?? 800,
        temperatureC: ((j['temperature_c'] as num?) ?? 25).toDouble(),
        volume: ((j['volume'] as num?) ?? 1).toDouble(),
        playId: j['play_id'] as String?,
        playedAtMs: (j['played_at'] as num?)?.toInt(),
      );
}
