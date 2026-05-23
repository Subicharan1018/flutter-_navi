// =============================================================================
// ListeningStatsResponse — model for GET /listening-log/stats (v3.0.0)
// =============================================================================

/// Aggregate listening statistics for a given period.
class ListeningStatsResponse {
  final String period;
  final String label;
  final int totalPlays;
  final int totalMinutes;
  final double avgListenRatio;
  final double skipRate;
  final int streakDays;
  final List<Map<String, dynamic>> topArtists;
  final List<Map<String, dynamic>> topAlbums;
  final List<Map<String, dynamic>> topTracks;
  final List<Map<String, dynamic>> recentPlays;
  final List<Map<String, dynamic>> genreBreakdown;
  final Map<String, int> hourlyHeatmap;

  const ListeningStatsResponse({
    required this.period,
    required this.label,
    required this.totalPlays,
    required this.totalMinutes,
    required this.avgListenRatio,
    required this.skipRate,
    required this.streakDays,
    required this.topArtists,
    required this.topAlbums,
    required this.topTracks,
    required this.recentPlays,
    required this.genreBreakdown,
    required this.hourlyHeatmap,
  });

  factory ListeningStatsResponse.fromJson(Map<String, dynamic> json) =>
      ListeningStatsResponse(
        period: json['period']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        totalPlays: _parseInt(json['total_plays']),
        totalMinutes: _parseInt(json['total_minutes']),
        avgListenRatio: _parseDouble(json['avg_listen_ratio']),
        skipRate: _parseDouble(json['skip_rate']),
        streakDays: _parseInt(json['streak_days']),
        topArtists: _parseList(json['top_artists']),
        topAlbums: _parseList(json['top_albums']),
        topTracks: _parseList(json['top_tracks']),
        recentPlays: _parseList(json['recent_plays']),
        genreBreakdown: _parseList(json['genre_breakdown']),
        hourlyHeatmap: _parseHeatmap(json['hourly_heatmap']),
      );

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

  static List<Map<String, dynamic>> _parseList(dynamic v) {
    if (v is List) return v.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  static Map<String, int> _parseHeatmap(dynamic v) {
    if (v is! Map) return {};
    return Map.fromEntries(
      v.entries.map((e) => MapEntry(
            e.key.toString(),
            e.value is int
                ? e.value as int
                : int.tryParse(e.value?.toString() ?? '') ?? 0,
          )),
    );
  }
}
