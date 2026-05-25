// =============================================================================
// FeedbackRequest — payload for POST /feedback (v3.0.0)
// =============================================================================

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
    required this.filePath,
    required this.genreBucket,
    required this.composer,
    required this.listenRatio,
    required this.endReason,
    required this.sessionId,
    required this.sessionDepth,
    this.genreStreakType = '',
    this.genreStreakCount = 0,
    this.weatherCode = 800,
    this.temperatureC = 25.0,
    this.volume = 1.0,
  });

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
