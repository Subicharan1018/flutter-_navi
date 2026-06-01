// lib/features/ai_shuffle/data/models/predict_response.dart

import 'dart:convert';
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
    final weatherObj = json['weather'] as Map<String, dynamic>?;
    final flatMood = json['weather_mood'] as String?;

    return PredictContext(
      bucket:        json['bucket'] as String,
      fallbackLevel: json['fallback_level'] as int? ?? 0,
      nInProfile:    json['n_in_profile'] as int? ?? 0,
      weatherMood:   weatherObj?['mood'] as String?
                     ?? flatMood
                     ?? 'clear',
      weatherCode:   weatherObj?['code'] as int?,
      temperatureC:  (weatherObj?['temperature_c'] as num?)?.toDouble(),
      maxPriorPlays: json['max_prior_plays'] as int?,
      timestampIst:  json['timestamp_ist'] as String? ?? '',
    );
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

    return PredictResponse(
      requestContext: PredictContext.fromJson(
        json['request_context'] as Map<String, dynamic>,
      ),
      count: json['count'] as int? ?? rawList.length,
      songs: rawList
          .cast<Map<String, dynamic>>()
          .map(RecommendedSong.fromPredictJson)
          .toList(),
      mode: mode,
    );
  }
}
