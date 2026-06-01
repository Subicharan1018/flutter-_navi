// =============================================================================
// RecommendedSong — a single queue entry from the v4.0.0 Smart Shuffle server.
// =============================================================================

/// Audio features for a song.
class AudioFeatures {
  final double energy;
  final double valence;
  final double acousticness;
  final double danceability;

  const AudioFeatures({
    required this.energy,
    required this.valence,
    required this.acousticness,
    required this.danceability,
  });

  factory AudioFeatures.fromJson(Map<String, dynamic> json) => AudioFeatures(
    energy: _parseDouble(json['energy']),
    valence: _parseDouble(json['valence']),
    acousticness: _parseDouble(json['acousticness']),
    danceability: _parseDouble(json['danceability']),
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

/// One song recommendation returned by the `/next` endpoint (v4.0.0).
class RecommendedSong {
  final int rank;
  final String title;
  final String filePath;
  final String genreBucket;
  final String composer;
  final AudioFeatures audio;
  final SongScores scores;

  // New fields from predict endpoints
  final String? artist;
  final String? album;
  final double? tempo;
  final double? tempoNorm;
  
  // Legacy fields mapped from scores if needed
  final double? historyScore;
  final double? audioFitScore;
  final double? composerScore;
  final double? finalScore;

  /// Human-readable explanation of why this song was chosen.
  final String why;

  // Legacy fields kept for display compatibility
  String get legacyArtist => artist ?? composer;
  String get legacyAlbum => album ?? genreBucket;

  const RecommendedSong({
    required this.rank,
    required this.title,
    required this.filePath,
    required this.genreBucket,
    required this.composer,
    required this.audio,
    required this.scores,
    required this.why,
    this.artist,
    this.album,
    this.tempo,
    this.tempoNorm,
    this.historyScore,
    this.audioFitScore,
    this.composerScore,
    this.finalScore,
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
            : const AudioFeatures(
                energy: 0,
                valence: 0,
                acousticness: 0,
                danceability: 0,
              ),
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

  static RecommendedSong fromPredictJson(Map<String, dynamic> json) {
    final af = json['audio_features'] as Map<String, dynamic>? ?? {};
    final sc = json['scores']        as Map<String, dynamic>? ?? {};

    return RecommendedSong(
      rank:          _parseInt(json['rank']),
      title:         json['title']?.toString() ?? json['song_key']?.toString() ?? '',
      // Newly available fields:
      artist:        json['artist']   as String?,
      album:         json['album']    as String?,
      // Moved inside audio_features:
      filePath:      af['file_path']  as String? ?? '',
      genreBucket:   af['genre_bucket'] as String? ?? '',
      audio: AudioFeatures(
        energy:       (af['energy']       as num?)?.toDouble() ?? 0.0,
        valence:      (af['valence']      as num?)?.toDouble() ?? 0.0,
        acousticness: (af['acousticness'] as num?)?.toDouble() ?? 0.0,
        danceability: (af['danceability'] as num?)?.toDouble() ?? 0.0,
      ),
      scores: SongScores(
        contextHistory:  (sc['history']   as num?)?.toDouble() ?? 0.0,
        audioFit:        (sc['audio_fit'] as num?)?.toDouble() ?? 0.0,
        composerLoyalty: (sc['composer']  as num?)?.toDouble() ?? 0.0,
        finalScore:      (sc['final']     as num?)?.toDouble() ?? 0.0,
      ),
      
      tempo:         (af['tempo']         as num?)?.toDouble(),
      tempoNorm:     (af['tempo_norm']    as num?)?.toDouble(),
      composer:      json['composer']     as String? ?? '',
      // Score keys renamed:
      historyScore:  (sc['history']   as num?)?.toDouble() ?? 0.0,   
      audioFitScore: (sc['audio_fit'] as num?)?.toDouble() ?? 0.0,
      composerScore: (sc['composer']  as num?)?.toDouble() ?? 0.0,   
      finalScore:    (sc['final']     as num?)?.toDouble() ?? 0.0,
      why:           json['why']      as String? ?? '',
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Shows a cold-start badge when the model has low confidence.
  bool get isColdStart => scores.finalScore < 0.4;
}
