/// Today's charts as the server's `GET /fetch/trending` reports them
/// (tg-fetcher's trending module): seven charts, up to 50 songs each, with
/// today's rank, movement since the last edition and, when the song is in the
/// library, its Navidrome id.
library;

/// Where a song moved since the chart's previous edition. Null on a chart's
/// first day (nothing to compare with), as Apple Music shows no marker then.
enum ChartMovement { up, down, same, isNew }

/// Whether a chart song can be played from the library.
enum ChartSongStatus {
  /// In the library: tap to play.
  available,

  /// Still being downloaded (or waiting its turn).
  pending,

  /// The download source only has it in lossy quality.
  lossy,

  /// No matching song on the download source.
  notFound,

  /// The download failed (retried on a later day).
  failed;

  static ChartSongStatus parse(Object? v) => switch (v) {
        'available' => available,
        'lossy' => lossy,
        'not_found' => notFound,
        'failed' => failed,
        _ => pending,
      };
}

class ChartEntry {
  final int rank;
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;

  /// Navidrome song id when the song is in the library.
  final String? songId;
  final ChartSongStatus status;

  /// Why it can't be played, from the server ("Only available in lossy quality").
  final String? reason;
  final ChartMovement? movement;

  /// Places moved up or down (0 for new / same).
  final int change;
  final int? previousRank;

  const ChartEntry({
    required this.rank,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverUrl,
    this.songId,
    this.status = ChartSongStatus.pending,
    this.reason,
    this.movement,
    this.change = 0,
    this.previousRank,
  });

  bool get playable => songId != null && songId!.isNotEmpty;

  /// The line under the artist when the song can't be played.
  String? get unavailableLine {
    if (playable) return null;
    if (status == ChartSongStatus.pending) return 'Downloading soon';
    return reason ?? switch (status) {
      ChartSongStatus.lossy => 'Only available in lossy quality',
      ChartSongStatus.notFound => 'Not found on the download source',
      _ => 'Download failed',
    };
  }

  factory ChartEntry.fromJson(Map<String, dynamic> j) {
    final songId = j['song_id'] as String?;
    return ChartEntry(
      rank: (j['rank'] as num?)?.toInt() ?? 0,
      title: j['title'] as String? ?? '',
      artist: j['artist'] as String? ?? '',
      album: j['album'] as String? ?? '',
      coverUrl: j['cover_url'] as String?,
      songId: (songId == null || songId.isEmpty) ? null : songId,
      status: ChartSongStatus.parse(j['status']),
      reason: j['reason'] as String?,
      movement: switch (j['movement']) {
        'up' => ChartMovement.up,
        'down' => ChartMovement.down,
        'same' => ChartMovement.same,
        'new' => ChartMovement.isNew,
        _ => null,
      },
      change: (j['change'] as num?)?.toInt() ?? 0,
      previousRank: (j['previous_rank'] as num?)?.toInt(),
    );
  }
}

class TrendingChart {
  /// tamil | english | hindi | malayalam | worldwide | india | tamil_nadu
  final String key;
  final String title;

  /// What the chart actually is ("JioSaavn · Tamil: India Superhits Top 50").
  final String source;

  /// Set when the chart stands in for one that couldn't be sourced.
  final String? note;

  /// The IST day of this edition, null before the first snapshot.
  final DateTime? date;
  final List<ChartEntry> entries;

  const TrendingChart({
    required this.key,
    required this.title,
    required this.source,
    this.note,
    this.date,
    this.entries = const [],
  });

  int get playableCount => entries.where((e) => e.playable).length;

  factory TrendingChart.fromJson(Map<String, dynamic> j) => TrendingChart(
        key: j['key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        source: j['source'] as String? ?? '',
        note: j['note'] as String?,
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        entries: [
          for (final e in (j['entries'] as List? ?? const []))
            if (e is Map) ChartEntry.fromJson(Map<String, dynamic>.from(e)),
        ]..sort((a, b) => a.rank.compareTo(b.rank)),
      );
}

class TrendingCharts {
  final List<TrendingChart> charts;
  const TrendingCharts(this.charts);

  /// Charts with at least one song, in the server's order.
  List<TrendingChart> get withSongs => [for (final c in charts) if (c.entries.isNotEmpty) c];

  factory TrendingCharts.fromJson(Map<String, dynamic> j) => TrendingCharts([
        for (final c in (j['charts'] as List? ?? const []))
          if (c is Map) TrendingChart.fromJson(Map<String, dynamic>.from(c)),
      ]);
}
