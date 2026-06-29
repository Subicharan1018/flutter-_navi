// lib/features/ai_shuffle/data/models/predict_response.dart

import 'recommended_song.dart';

/// Selects which predictive endpoint to call and how to parse the response.
enum PredictMode { alwaysHear, discovery }

extension PredictModeLabel on PredictMode {
  String get displayLabel {
    switch (this) {
      case PredictMode.alwaysHear: return 'Always Hear';
      case PredictMode.discovery:  return 'Discovery';
    }
  }

  String get emptyMessage {
    switch (this) {
      case PredictMode.alwaysHear:
        return 'Not enough listening history for this context yet. Keep playing music!';
      case PredictMode.discovery:
        return 'No unexplored songs match your current vibe. Try raising max_prior_plays.';
    }
  }
}

/// The `request_context` block returned by both predict endpoints.
/// Handles both always-hear (weather as nested object) and
/// discovery (weather_mood as flat string) response shapes.
class PredictContext {
  const PredictContext({
    required this.bucket,
    required this.fallbackLevel,
    required this.nInProfile,
    required this.weatherMood,
    this.weatherCode,
    this.temperatureC,
    this.maxPriorPlays,
    required this.timestampIst,
  });

  final String bucket;         // e.g. "late_morning__summer__cloudy"
  final int fallbackLevel;     // 0 = exact, 1 = season, 2 = time-only, 3 = global
  final int nInProfile;        // plays that built the active taste profile
  final String weatherMood;    // "clear" | "cloudy" | "rainy" | "stormy"
  final int? weatherCode;      // WMO code (only from always-hear)
  final double? temperatureC;  // only from always-hear
  final int? maxPriorPlays;    // only from discovery
  final String timestampIst;   // ISO-8601 with +05:30

  // ── Derived convenience getters ─────────────────────────────────────────

  /// "late_morning__summer__cloudy" → "late_morning"
  String get timeSlot => bucket.split('__').elementAtOrNull(0) ?? '';

  /// "late_morning__summer__cloudy" → "summer"
  String get season => bucket.split('__').elementAtOrNull(1) ?? '';

  /// Human-readable description of fallback level for the UI banner.
  String get fallbackDescription {
    switch (fallbackLevel) {
      case 0: return 'Exact context match ($nInProfile plays)';
      case 1: return 'Season fallback ($nInProfile plays)';
      case 2: return 'Time-of-day fallback ($nInProfile plays)';
      case 3: return 'Global profile (cold start — listen more to personalise)';
      default: return 'Profile level $fallbackLevel';
    }
  }

  /// True when we have high-confidence personalised results.
  bool get isHighConfidence => fallbackLevel == 0;

  factory PredictContext.fromJson(Map<String, dynamic> json) {
    // always-hear: weather is a nested Map { "code", "mood", "temperature_c" }
    // discovery:   weather_mood is a flat String
    final weatherObj = json['weather'] is Map ? Map<String, dynamic>.from(json['weather'] as Map) : null;
    final flatMood = json['weather_mood']?.toString();

    return PredictContext(
      bucket:        json['bucket']?.toString() ?? '',
      fallbackLevel: _parseInt(json['fallback_level']),
      nInProfile:    _parseInt(json['n_in_profile']),
      weatherMood:   weatherObj?['mood']?.toString()
                     ?? flatMood
                     ?? 'clear',
      weatherCode:   weatherObj != null ? _parseIntOrNull(weatherObj['code']) : _parseIntOrNull(json['weather_code']),
      temperatureC:  weatherObj != null ? _parseDoubleOrNull(weatherObj['temperature_c']) : _parseDoubleOrNull(json['temperature_c']),
      maxPriorPlays: _parseIntOrNull(json['max_prior_plays']),
      timestampIst:  json['timestamp_ist']?.toString() ?? '',
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _parseDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _parseIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  String toString() =>
      'PredictContext(bucket: $bucket, fallback: $fallbackLevel, '
      'n: $nInProfile, weather: $weatherMood)';
}

/// The parsed top-level response from either predictive endpoint.
class PredictResponse {
  const PredictResponse({
    required this.requestContext,
    required this.count,
    required this.songs,
    required this.mode,
  });

  final PredictContext requestContext;
  final int count;
  final List<RecommendedSong> songs;
  final PredictMode mode;

  bool get isEmpty => songs.isEmpty;

  factory PredictResponse.fromJson(
    Map<String, dynamic> json,
    PredictMode mode,
  ) {
    // always-hear → "predictions"; discovery → "discovery_pool"
    final rawList =
        (json['predictions'] ?? json['discovery_pool']) as List<dynamic>? ?? [];

    final requestContextJson = json['request_context'];
    final requestContext = requestContextJson is Map
        ? PredictContext.fromJson(Map<String, dynamic>.from(requestContextJson))
        : const PredictContext(
            bucket: '',
            fallbackLevel: 3,
            nInProfile: 0,
            weatherMood: 'clear',
            timestampIst: '',
          );

    return PredictResponse(
      requestContext: requestContext,
      count: json['count'] as int? ?? rawList.length,
      songs: rawList
          .whereType<Map>()
          .map((e) => RecommendedSong.fromPredictJson(Map<String, dynamic>.from(e)))
          .toList(),
      mode: mode,
    );
  }
}
