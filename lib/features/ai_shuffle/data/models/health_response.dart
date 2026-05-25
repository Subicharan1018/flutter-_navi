// =============================================================================
// HealthResponse — model for GET /health (v3.0.0)
// =============================================================================

/// Server health status returned by the `/health` endpoint.
class HealthResponse {
  final String status;
  final WeatherInfo? weather;

  const HealthResponse({required this.status, this.weather});

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
    status: json['status']?.toString() ?? 'unknown',
    weather: json['weather'] is Map<String, dynamic>
        ? WeatherInfo.fromJson(json['weather'] as Map<String, dynamic>)
        : null,
  );

  bool get isHealthy => status == 'ok' || status == 'healthy';
}

/// Weather info embedded in /health response.
class WeatherInfo {
  final int code;
  final String mood;
  final double temperatureC;
  final int humidityPct;
  final String fetchedAt;

  const WeatherInfo({
    required this.code,
    required this.mood,
    required this.temperatureC,
    required this.humidityPct,
    required this.fetchedAt,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) => WeatherInfo(
    code: _parseInt(json['code']),
    mood: json['mood']?.toString() ?? 'clear',
    temperatureC: _parseDouble(json['temperature_c']),
    humidityPct: _parseInt(json['humidity_pct']),
    fetchedAt: json['fetched_at']?.toString() ?? '',
  );

  /// Returns a weather emoji for the mood string.
  String get moodIcon {
    switch (mood) {
      case 'rainy':
        return '🌧';
      case 'stormy':
        return '⛈';
      case 'cloudy':
        return '☁';
      case 'clear':
      default:
        return '☀';
    }
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
