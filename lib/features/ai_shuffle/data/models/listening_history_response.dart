// =============================================================================
// ListeningHistoryResponse — model for GET /listening-log/history (v3.0.0)
// =============================================================================

/// A single play history item.
class PlayHistoryItem {
  final String title;
  final String artist;
  final String album;
  final String playedAtIst;
  final double listenRatio;
  final String endReason;
  final String genre;

  const PlayHistoryItem({
    required this.title,
    required this.artist,
    required this.album,
    required this.playedAtIst,
    required this.listenRatio,
    required this.endReason,
    required this.genre,
  });

  factory PlayHistoryItem.fromJson(Map<String, dynamic> json) =>
      PlayHistoryItem(
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString() ?? '',
        playedAtIst: json['played_at_ist']?.toString() ?? '',
        listenRatio: _parseDouble(json['listen_ratio']),
        endReason: json['end_reason']?.toString() ?? '',
        genre: json['genre']?.toString() ?? '',
      );

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Paginated play history response.
class ListeningHistoryResponse {
  final int total;
  final int offset;
  final int limit;
  final List<PlayHistoryItem> items;

  const ListeningHistoryResponse({
    required this.total,
    required this.offset,
    required this.limit,
    required this.items,
  });

  factory ListeningHistoryResponse.fromJson(Map<String, dynamic> json) =>
      ListeningHistoryResponse(
        total: _parseInt(json['total']),
        offset: _parseInt(json['offset']),
        limit: _parseInt(json['limit']),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => PlayHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
