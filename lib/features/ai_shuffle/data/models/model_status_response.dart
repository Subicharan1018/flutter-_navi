// =============================================================================
// ModelStatusResponse — model for GET /model/status (v3.0.0)
// =============================================================================

/// Model build state returned by `/model/status`.
class ModelStatusResponse {
  final String username;
  final String builtAt;
  final int totalPlaysProcessed;
  final int songsInLibrary;
  final int composersTracked;
  final int contextBuckets;
  final int unprocessedEvents;
  final double modelSizeMb;
  final int rebuildThreshold;
  // ── Session model (server v3.1) ───────────────────────────────────────────
  /// Number of songs with at least one learned pairing.
  final int songsWithPairings;
  /// Number of time-of-day contexts that have learned session starters.
  final int starterContexts;

  const ModelStatusResponse({
    required this.username,
    required this.builtAt,
    required this.totalPlaysProcessed,
    required this.songsInLibrary,
    required this.composersTracked,
    required this.contextBuckets,
    required this.unprocessedEvents,
    required this.modelSizeMb,
    required this.rebuildThreshold,
    this.songsWithPairings = 0,
    this.starterContexts = 0,
  });

  factory ModelStatusResponse.fromJson(Map<String, dynamic> json) =>
      ModelStatusResponse(
        username: json['username']?.toString() ?? '',
        builtAt: json['built_at']?.toString() ?? '',
        totalPlaysProcessed: _parseInt(json['total_plays_processed']),
        songsInLibrary: _parseInt(json['songs_in_library']),
        composersTracked: _parseInt(json['composers_tracked']),
        contextBuckets: _parseInt(json['context_buckets']),
        unprocessedEvents: _parseInt(json['unprocessed_events']),
        modelSizeMb: _parseDouble(json['model_size_mb']),
        rebuildThreshold: _parseInt(json['rebuild_threshold']),
        songsWithPairings: _parseInt(json['songs_with_pairings']),
        starterContexts: _parseInt(json['starter_contexts']),
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

  /// Human-readable build timestamp.
  String get builtAtFormatted {
    final dt = DateTime.tryParse(builtAt);
    if (dt == null) return builtAt;
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
}
