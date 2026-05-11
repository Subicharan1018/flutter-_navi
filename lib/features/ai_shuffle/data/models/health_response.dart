// =============================================================================
// HealthResponse — model for GET /health
// =============================================================================

/// Server health status returned by the `/health` endpoint.
class HealthResponse {
  final String status;
  final String uptime;
  final int librarySize;
  final bool modelLoaded;

  const HealthResponse({
    required this.status,
    required this.uptime,
    required this.librarySize,
    required this.modelLoaded,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
        status: json['status']?.toString() ?? 'unknown',
        uptime: json['uptime']?.toString() ?? '',
        librarySize: _parseInt(json['library_size']),
        modelLoaded: json['model_loaded'] == true,
      );

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get isHealthy => status == 'ok' || status == 'healthy';
}
