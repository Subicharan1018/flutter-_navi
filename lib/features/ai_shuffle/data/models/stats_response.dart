// =============================================================================
// ShuffleStatsResponse — model for GET /stats
// =============================================================================

/// Aggregate playback statistics returned by the `/stats` endpoint.
class ShuffleStatsResponse {
  final int totalPlays;
  final List<Map<String, dynamic>> topSongs;
  final List<Map<String, dynamic>> topArtists;
  final Map<String, dynamic> weekly;
  final Map<String, dynamic> monthly;

  const ShuffleStatsResponse({
    required this.totalPlays,
    required this.topSongs,
    required this.topArtists,
    required this.weekly,
    required this.monthly,
  });

  factory ShuffleStatsResponse.fromJson(Map<String, dynamic> json) =>
      ShuffleStatsResponse(
        totalPlays: _parseInt(json['total_plays']),
        topSongs: _parseList(json['top_songs']),
        topArtists: _parseList(json['top_artists']),
        weekly: (json['weekly'] as Map<String, dynamic>?) ?? {},
        monthly: (json['monthly'] as Map<String, dynamic>?) ?? {},
      );

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _parseList(dynamic value) {
    if (value is List<dynamic>) {
      return value
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }
}
