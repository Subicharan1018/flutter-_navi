// =============================================================================
// ListeningStats — data models for the /listening-log/stats API response.
// =============================================================================

/// Top-level response from GET /listening-log/stats?period=...
class ListeningStats {
  final String period;
  final String label;
  final int totalPlays;
  final int totalMinutes;
  final List<ArtistStat> topArtists;
  final List<AlbumStat> topAlbums;
  final List<TrackStat> topTracks;
  final List<RecentPlay> recentPlays;

  const ListeningStats({
    required this.period,
    required this.label,
    required this.totalPlays,
    required this.totalMinutes,
    required this.topArtists,
    required this.topAlbums,
    required this.topTracks,
    required this.recentPlays,
  });

  factory ListeningStats.fromJson(Map<String, dynamic> json) {
    return ListeningStats(
      period: json['period']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      totalPlays: _parseInt(json['total_plays']),
      totalMinutes: _parseInt(json['total_minutes']),
      topArtists: (json['top_artists'] as List<dynamic>? ?? [])
          .map((e) => ArtistStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      topAlbums: (json['top_albums'] as List<dynamic>? ?? [])
          .map((e) => AlbumStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      topTracks: (json['top_tracks'] as List<dynamic>? ?? [])
          .map((e) => TrackStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentPlays: (json['recent_plays'] as List<dynamic>? ?? [])
          .map((e) => RecentPlay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// A single artist entry in the top-artists list.
class ArtistStat {
  final String artist;
  final int playCount;

  const ArtistStat({required this.artist, required this.playCount});

  factory ArtistStat.fromJson(Map<String, dynamic> json) => ArtistStat(
    artist: json['artist']?.toString() ?? 'Unknown Artist',
    playCount: ListeningStats._parseInt(json['play_count']),
  );
}

/// A single album entry in the top-albums list.
class AlbumStat {
  final String album;
  final String artist;
  final int playCount;

  const AlbumStat({
    required this.album,
    required this.artist,
    required this.playCount,
  });

  factory AlbumStat.fromJson(Map<String, dynamic> json) => AlbumStat(
    album: json['album']?.toString() ?? 'Unknown Album',
    artist: json['artist']?.toString() ?? 'Unknown Artist',
    playCount: ListeningStats._parseInt(json['play_count']),
  );
}

/// A single track entry in the top-tracks list.
class TrackStat {
  final String title;
  final String artist;
  final int playCount;

  const TrackStat({
    required this.title,
    required this.artist,
    required this.playCount,
  });

  factory TrackStat.fromJson(Map<String, dynamic> json) => TrackStat(
    title: json['title']?.toString() ?? 'Unknown Track',
    artist: json['artist']?.toString() ?? 'Unknown Artist',
    playCount: ListeningStats._parseInt(json['play_count']),
  );
}

/// A single entry in the recent-plays list.
class RecentPlay {
  final int id;
  final String playedAt; // ISO-8601 string from server
  final String title;
  final String artist;
  final String? album;
  final String? coverArt;

  const RecentPlay({
    required this.id,
    required this.playedAt,
    required this.title,
    required this.artist,
    this.album,
    this.coverArt,
  });

  factory RecentPlay.fromJson(Map<String, dynamic> json) => RecentPlay(
    id: ListeningStats._parseInt(json['id']),
    playedAt: json['played_at']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Unknown Track',
    artist: json['artist']?.toString() ?? 'Unknown Artist',
    album: json['album']?.toString(),
    coverArt: json['cover_art']?.toString(),
  );

  /// Returns a human-readable "time ago" string without any external package.
  String get timeAgo {
    final dt = DateTime.tryParse(playedAt);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
