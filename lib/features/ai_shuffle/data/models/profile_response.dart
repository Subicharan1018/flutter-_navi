// =============================================================================
// ProfileResponse — model for GET /profile?song=...
// =============================================================================

/// Song behavioural + acoustic profile returned by the `/profile` endpoint.
class ProfileResponse {
  final String song;

  /// Behavioural signals: play_count, skip_rate, completion_rate, etc.
  final Map<String, dynamic> behavioural;

  /// Acoustic features: bpm, key, energy, danceability, etc.
  final Map<String, dynamic> acoustic;

  final int playCount;

  const ProfileResponse({
    required this.song,
    required this.behavioural,
    required this.acoustic,
    required this.playCount,
  });

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      ProfileResponse(
        song: json['song']?.toString() ?? '',
        behavioural: (json['behavioural'] as Map<String, dynamic>?) ?? {},
        acoustic: (json['acoustic'] as Map<String, dynamic>?) ?? {},
        playCount: _parseInt(json['play_count']),
      );

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
