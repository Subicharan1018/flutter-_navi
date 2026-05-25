// =============================================================================
// RecommendedSong — a single queue entry from the v3.0.0 Smart Shuffle server.
// =============================================================================

/// Audio features for a song.
class AudioFeatures {
  final double energy;
  final double valence;
  final double acousticness;

  const AudioFeatures({
    required this.energy,
    required this.valence,
    required this.acousticness,
  });

  factory AudioFeatures.fromJson(Map<String, dynamic> json) => AudioFeatures(
    energy: _parseDouble(json['energy']),
    valence: _parseDouble(json['valence']),
    acousticness: _parseDouble(json['acousticness']),
  );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Score breakdown for a song.
class SongScores {
  final double contextHistory;
  final double audioFit;
  final double composerLoyalty;
  final double finalScore;

  const SongScores({
    required this.contextHistory,
    required this.audioFit,
    required this.composerLoyalty,
    required this.finalScore,
  });

  factory SongScores.fromJson(Map<String, dynamic> json) => SongScores(
    contextHistory: _parseDouble(json['context_history']),
    audioFit: _parseDouble(json['audio_fit']),
    composerLoyalty: _parseDouble(json['composer_loyalty']),
    finalScore: _parseDouble(json['final']),
  );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// One song recommendation returned by the `/next` endpoint (v3.0.0).
class RecommendedSong {
  final int rank;
  final String title;
  final String filePath;
  final String genreBucket;
  final String composer;
  final AudioFeatures audio;
  final SongScores scores;

  /// Human-readable explanation of why this song was chosen.
  final String why;

  // Legacy fields kept for display compatibility
  String get artist => composer;
  String get album => genreBucket;

  const RecommendedSong({
    required this.rank,
    required this.title,
    required this.filePath,
    required this.genreBucket,
    required this.composer,
    required this.audio,
    required this.scores,
    required this.why,
  });

  factory RecommendedSong.fromJson(Map<String, dynamic> json) =>
      RecommendedSong(
        rank: _parseInt(json['rank']),
        title: json['title']?.toString() ?? json['song_key']?.toString() ?? '',
        filePath: json['file_path']?.toString() ?? '',
        genreBucket: json['genre_bucket']?.toString() ?? '',
        composer: json['composer']?.toString() ?? '',
        audio: json['audio'] is Map<String, dynamic>
            ? AudioFeatures.fromJson(json['audio'] as Map<String, dynamic>)
            : const AudioFeatures(energy: 0, valence: 0, acousticness: 0),
        scores: json['scores'] is Map<String, dynamic>
            ? SongScores.fromJson(json['scores'] as Map<String, dynamic>)
            : const SongScores(
                contextHistory: 0,
                audioFit: 0,
                composerLoyalty: 0,
                finalScore: 0,
              ),
        why: json['why']?.toString() ?? '',
      );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Shows a cold-start badge when the model has low confidence.
  bool get isColdStart => scores.finalScore < 0.4;
}
