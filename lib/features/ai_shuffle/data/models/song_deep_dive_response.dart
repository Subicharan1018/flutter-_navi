// =============================================================================
// SongDeepDiveResponse — response from GET /listening-log/song (v4.0.0)
// =============================================================================

/// Audio features returned in the song deep-dive response.
class DeepDiveAudioFeatures {
  final double energy;
  final double valence;
  final double acousticness;
  final double danceability;
  final double tempo;

  const DeepDiveAudioFeatures({
    required this.energy,
    required this.valence,
    required this.acousticness,
    required this.danceability,
    required this.tempo,
  });

  factory DeepDiveAudioFeatures.fromJson(Map<String, dynamic> json) =>
      DeepDiveAudioFeatures(
        energy: _parseDouble(json['energy']),
        valence: _parseDouble(json['valence']),
        acousticness: _parseDouble(json['acousticness']),
        danceability: _parseDouble(json['danceability']),
        tempo: _parseDouble(json['tempo']),
      );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// A context summary item (used for best/worst contexts).
class ContextSummary {
  final String contextBucket;
  final double avgRatio;
  final int playCount;

  const ContextSummary({
    required this.contextBucket,
    required this.avgRatio,
    required this.playCount,
  });

  factory ContextSummary.fromJson(Map<String, dynamic> json) => ContextSummary(
    contextBucket: json['context_bucket']?.toString() ?? '',
    avgRatio: _parseDouble(json['avg_ratio']),
    playCount: _parseInt(json['play_count']),
  );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// A single item in the context history array.
class ContextHistoryItem {
  final String contextBucket;
  final double avgRatio;
  final int playCount;

  const ContextHistoryItem({
    required this.contextBucket,
    required this.avgRatio,
    required this.playCount,
  });

  factory ContextHistoryItem.fromJson(Map<String, dynamic> json) =>
      ContextHistoryItem(
        contextBucket: json['context_bucket']?.toString() ?? '',
        avgRatio: _parseDouble(json['avg_ratio']),
        playCount: _parseInt(json['play_count']),
      );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// Full response from the `/listening-log/song` endpoint.
class SongDeepDiveResponse {
  final String title;
  final String composer;
  final String genreBucket;
  final DeepDiveAudioFeatures audioFeatures;
  final int totalPlays;
  final int genuinePlays;
  final ContextSummary? bestContext;
  final ContextSummary? worstContext;
  final List<ContextHistoryItem> contextHistory;

  const SongDeepDiveResponse({
    required this.title,
    required this.composer,
    required this.genreBucket,
    required this.audioFeatures,
    required this.totalPlays,
    required this.genuinePlays,
    this.bestContext,
    this.worstContext,
    required this.contextHistory,
  });

  factory SongDeepDiveResponse.fromJson(
    Map<String, dynamic> json,
  ) => SongDeepDiveResponse(
    title: json['title']?.toString() ?? '',
    composer: json['composer']?.toString() ?? '',
    genreBucket: json['genre_bucket']?.toString() ?? '',
    audioFeatures: json['audio_features'] is Map
        ? DeepDiveAudioFeatures.fromJson(
            Map<String, dynamic>.from(json['audio_features'] as Map),
          )
        : const DeepDiveAudioFeatures(
            energy: 0,
            valence: 0,
            acousticness: 0,
            danceability: 0,
            tempo: 0,
          ),
    totalPlays: _parseInt(json['total_plays']),
    genuinePlays: _parseInt(json['genuine_plays']),
    bestContext: json['best_context'] is Map
        ? ContextSummary.fromJson(Map<String, dynamic>.from(json['best_context'] as Map))
        : null,
    worstContext: json['worst_context'] is Map
        ? ContextSummary.fromJson(Map<String, dynamic>.from(json['worst_context'] as Map))
        : null,
    contextHistory: (json['context_history'] as List<dynamic>? ?? [])
        .map((e) => ContextHistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
