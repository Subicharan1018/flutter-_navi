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
  final String sessionId;
  final int sessionDepth;
  final String genreStreakType;
  final int genreStreakCount;
  final int weatherCode;
  final double temperatureC;
  final double volume;

  const FeedbackRequest({
    required this.title,
    required this.listenRatio,
    required this.endReason,
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
    'session_id': sessionId,
    'session_depth': sessionDepth,
    'genre_streak_type': genreStreakType,
    'genre_streak_count': genreStreakCount,
    'weather_code': weatherCode,
    'temperature_c': temperatureC,
    'volume': volume,
  };
}
