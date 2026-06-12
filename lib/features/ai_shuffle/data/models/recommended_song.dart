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

/// A learned song-to-song pairing (server v3.1). Present on `/next` queue
/// entries that were placed adjacent to the song they historically follow.
class SongPairing {
  /// The title this song habitually follows in the user's sessions.
  final String follows;

  /// How many times this transition was observed.
  final int timesFollowed;

  /// p(this | previous) — 0..1 transition probability out of `follows`.
  final double probability;

  const SongPairing({
    required this.follows,
    required this.timesFollowed,
    required this.probability,
  });

  factory SongPairing.fromJson(Map<String, dynamic> json) => SongPairing(
    follows: json['follows']?.toString() ?? '',
    timesFollowed: RecommendedSong._parseInt(json['times_followed']),
    probability: RecommendedSong._parseDouble(json['p']),
  );
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

  // ── Session-aware fields (server v3.1) ────────────────────────────────────
  /// True when this song is the user's habitual session opener for this
  /// time-of-day (only set on `/next` at the start of a session).
  final bool isStarter;

  /// True when this song is the queue's single "exploration" pick
  /// (never played before, chosen by audio fit).
  final bool isExplore;

  /// Set when this song was ordered next to the song it historically follows.
  final SongPairing? pairing;

  // ── /predict/always-hear loyalty fields (server v3.1) ─────────────────────
  /// Overall loyalty score for this context (0..1). Drives the MATCH bar in
  /// Always-Hear mode (there is no `final` score for that endpoint anymore).
  final double? loyalty;

  /// How concentrated this song is in the *current* context (0..1).
  final double? contextFit;

  /// Average listen completion ratio (0..1).
  final double? completionAvg;

  /// Recency signal — 0.5^(days_since_last_listen / 30), 0..1.
  final double? recencyDecay;

  /// Days since the song was last genuinely played (null if unknown).
  final int? daysSincePlay;

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
    this.isStarter = false,
    this.isExplore = false,
    this.pairing,
    this.loyalty,
    this.contextFit,
    this.completionAvg,
    this.recencyDecay,
    this.daysSincePlay,
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
        isStarter: json['starter'] == true,
        isExplore: json['explore'] == true,
        pairing: json['pairing'] is Map<String, dynamic>
            ? SongPairing.fromJson(json['pairing'] as Map<String, dynamic>)
            : null,
      );

  static RecommendedSong fromPredictJson(Map<String, dynamic> json) {
    final af = json['audio_features'] as Map<String, dynamic>? ?? {};
    final sc = json['scores']        as Map<String, dynamic>? ?? {};
    final cs = json['context_stats'] as Map<String, dynamic>? ?? {};

    // always-hear (v3.1) scores: {loyalty, completion_avg, freq_norm,
    //   context_fit, context_spread, recency_decay} — no `final`/`audio_fit`.
    // discovery scores: {audio_fit, composer, final}.
    // Fall back across both shapes so the MATCH bar stays meaningful.
    final loyalty       = (sc['loyalty']        as num?)?.toDouble();
    final contextFit    = (sc['context_fit']    as num?)?.toDouble();
    final completionAvg = (sc['completion_avg'] as num?)?.toDouble();
    final recencyDecay  = (sc['recency_decay']  as num?)?.toDouble();
    final overall = (sc['final'] as num?)?.toDouble()
        ?? loyalty
        ?? 0.0;
    // For Always-Hear, "audio fit" in the score breakdown best maps to
    // context fit; Discovery keeps its real audio_fit.
    final audioFit = (sc['audio_fit'] as num?)?.toDouble()
        ?? contextFit
        ?? 0.0;

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
        audioFit:        audioFit,
        composerLoyalty: (sc['composer']  as num?)?.toDouble() ?? 0.0,
        finalScore:      overall,
      ),

      tempo:         (af['tempo']         as num?)?.toDouble(),
      tempoNorm:     (af['tempo_norm']    as num?)?.toDouble(),
      composer:      json['composer']     as String? ?? '',
      // Score keys renamed:
      historyScore:  (sc['history']   as num?)?.toDouble() ?? 0.0,
      audioFitScore: audioFit,
      composerScore: (sc['composer']  as num?)?.toDouble() ?? 0.0,
      finalScore:    overall,
      // v3.1 loyalty signals
      loyalty:       loyalty,
      contextFit:    contextFit,
      completionAvg: completionAvg,
      recencyDecay:  recencyDecay,
      daysSincePlay: cs['days_since_play'] == null
          ? null
          : _parseInt(cs['days_since_play']),
      why:           json['why']      as String? ?? '',
    );
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

  /// Shows a cold-start badge when the model has low confidence.
  /// Exploration picks are inherently low-score, so don't flag those.
  bool get isColdStart => !isExplore && scores.finalScore < 0.4;
}
