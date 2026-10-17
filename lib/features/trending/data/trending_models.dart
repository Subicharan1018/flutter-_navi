/// Today's charts as the server's `GET /fetch/trending` reports them
/// (tg-fetcher's trending module): the server's charts in its order, up to
/// 50 songs each, with today's rank, movement since the last edition, every
/// detail the chart's source prints (Billboard, JioSaavn) and, when the song
/// is in the library, its Navidrome id.
library;

/// Where a song moved since the chart's previous edition. Null on a chart's
/// first day (nothing to compare with), as Apple Music shows no marker then.
/// Billboard charts move by Billboard's own NEW / RE-ENTRY / last week.
enum ChartMovement { up, down, same, isNew, reentry }

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

/// What kind of chart it is, which decides which details its rows carry.
enum ChartKind {
  billboard,
  saavn,
  other;

  static ChartKind parse(Object? v) => switch (v) {
        'billboard' => billboard,
        'saavn' => saavn,
        _ => other,
      };
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String? _str(Object? v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;
List<String> _strs(Object? v) => [for (final x in (v is List ? v : const [])) if (_str(x) != null) _str(x)!];

/// A Billboard row, as billboard.com prints it.
class BillboardDetails {
  final int? lastWeek;
  final int? peak;
  final int? weeksOnChart;
  final int? weeksAtNo1;
  final int? debutPosition;

  /// As Billboard writes it ("10/17/26").
  final String? debutDate;
  final int? peakPosition;
  final String? peakDate;

  /// "Highest ranking debut", "Gains In Performance" …
  final List<String> awards;
  final List<String> songwriters;
  final List<String> producers;
  final String? label;

  const BillboardDetails({
    this.lastWeek,
    this.peak,
    this.weeksOnChart,
    this.weeksAtNo1,
    this.debutPosition,
    this.debutDate,
    this.peakPosition,
    this.peakDate,
    this.awards = const [],
    this.songwriters = const [],
    this.producers = const [],
    this.label,
  });

  factory BillboardDetails.fromJson(Map<String, dynamic> j) => BillboardDetails(
        lastWeek: _int(j['last_week']),
        peak: _int(j['peak']),
        weeksOnChart: _int(j['weeks_on_chart']),
        weeksAtNo1: _int(j['weeks_at_no1']),
        debutPosition: _int(j['debut_position']),
        debutDate: _str(j['debut_date']),
        peakPosition: _int(j['peak_position']),
        peakDate: _str(j['peak_date']),
        awards: _strs(j['awards']),
        songwriters: _strs(j['songwriters']),
        producers: _strs(j['producers']),
        label: _str(j['label']),
      );
}

/// What JioSaavn says about a chart song.
class SaavnDetails {
  final int? playCount;
  final int? year;
  final DateTime? releaseDate;
  final String? language;
  final String? label;
  final String? album;
  final int? durationS;
  final bool explicit;
  final List<String> music;
  final List<String> lyricists;
  final List<String> singers;
  final String? copyright;

  const SaavnDetails({
    this.playCount,
    this.year,
    this.releaseDate,
    this.language,
    this.label,
    this.album,
    this.durationS,
    this.explicit = false,
    this.music = const [],
    this.lyricists = const [],
    this.singers = const [],
    this.copyright,
  });

  factory SaavnDetails.fromJson(Map<String, dynamic> j) => SaavnDetails(
        playCount: _int(j['play_count']),
        year: _int(j['year']),
        releaseDate: DateTime.tryParse(j['release_date'] as String? ?? ''),
        language: _str(j['language']),
        label: _str(j['label']),
        album: _str(j['album']),
        durationS: _int(j['duration_s']),
        explicit: j['explicit'] == true,
        music: _strs(j['music']),
        lyricists: _strs(j['lyricists']),
        singers: _strs(j['singers']),
        copyright: _str(j['copyright']),
      );
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

  /// Set on Billboard charts / JioSaavn charts.
  final BillboardDetails? billboard;
  final SaavnDetails? saavn;

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
    this.billboard,
    this.saavn,
  });

  bool get playable => songId != null && songId!.isNotEmpty;

  /// Whether the row has more to show when expanded.
  bool get hasDetails => billboard != null || saavn != null;

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
    final details = j['details'] is Map ? Map<String, dynamic>.from(j['details'] as Map) : const <String, dynamic>{};
    final bb = details['billboard'];
    final sv = details['saavn'];
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
        'reentry' => ChartMovement.reentry,
        _ => null,
      },
      change: (j['change'] as num?)?.toInt() ?? 0,
      previousRank: (j['previous_rank'] as num?)?.toInt(),
      billboard: bb is Map ? BillboardDetails.fromJson(Map<String, dynamic>.from(bb)) : null,
      saavn: sv is Map ? SaavnDetails.fromJson(Map<String, dynamic>.from(sv)) : null,
    );
  }
}

class TrendingChart {
  /// tamil | english | hindi | malayalam | worldwide | india | tamil_nadu |
  /// billboard_hot_100 | billboard_global_200 (the server may add more)
  final String key;
  final String title;

  /// What the chart actually is ("JioSaavn · Tamil: India Superhits Top 50").
  final String source;
  final ChartKind kind;

  /// Set when the chart stands in for one that couldn't be sourced.
  final String? note;

  /// The IST day of this edition, null before the first snapshot.
  final DateTime? date;

  /// Billboard's chart week, as Billboard writes it ("October 17, 2026").
  final String? weekOf;

  /// The source's own line about the chart.
  final String? description;
  final List<ChartEntry> entries;

  const TrendingChart({
    required this.key,
    required this.title,
    required this.source,
    this.kind = ChartKind.other,
    this.note,
    this.date,
    this.weekOf,
    this.description,
    this.entries = const [],
  });

  int get playableCount => entries.where((e) => e.playable).length;

  factory TrendingChart.fromJson(Map<String, dynamic> j) => TrendingChart(
        key: j['key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        source: j['source'] as String? ?? '',
        kind: ChartKind.parse(j['kind']),
        note: j['note'] as String?,
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        weekOf: _str(j['week_of']),
        description: _str(j['description']),
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
