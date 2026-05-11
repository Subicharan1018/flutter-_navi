// =============================================================================
// RecommendedSong — a single recommendation entry from the AI shuffle server.
// =============================================================================

/// One song recommendation returned by the `/next` endpoint.
class RecommendedSong {
  final String title;
  final String artist;
  final String album;

  /// Model confidence score in [0.0, 1.0]. Higher = stronger recommendation.
  final double score;

  /// When true the model had insufficient history data and fell back to
  /// cold-start logic. The UI should display a COLD START badge.
  final bool coldStart;

  const RecommendedSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.score,
    required this.coldStart,
  });

  factory RecommendedSong.fromJson(Map<String, dynamic> json) =>
      RecommendedSong(
        title: json['title']?.toString() ?? json['song_key']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        score: _parseDouble(json['score']),
        coldStart: json['cold_start'] == true,
      );

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
