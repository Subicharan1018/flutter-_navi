// =============================================================================
// replay_response.dart — models for GET /replay and GET /replay/<year>/<month>
// =============================================================================

// ---------------------------------------------------------------------------
// Shared sub-models
// ---------------------------------------------------------------------------

class ReplayTrack {
  final String title;
  final String artist;
  final String album;
  final int playCount;
  final double totalMinutes;
  final double avgRatio;

  const ReplayTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.playCount,
    required this.totalMinutes,
    required this.avgRatio,
  });

  factory ReplayTrack.fromJson(Map<String, dynamic> j) => ReplayTrack(
    title: j['title']?.toString() ?? '',
    artist: j['artist']?.toString() ?? '',
    album: j['album']?.toString() ?? '',
    playCount: _parseInt(j['play_count']),
    totalMinutes: _parseDouble(j['total_minutes']),
    avgRatio: _parseDouble(j['avg_ratio']),
  );
}

class ReplayArtist {
  final String artist;
  final int playCount;
  final double totalMinutes;
  final int uniqueSongs;

  const ReplayArtist({
    required this.artist,
    required this.playCount,
    required this.totalMinutes,
    required this.uniqueSongs,
  });

  factory ReplayArtist.fromJson(Map<String, dynamic> j) => ReplayArtist(
    artist: j['artist']?.toString() ?? '',
    playCount: _parseInt(j['play_count']),
    totalMinutes: _parseDouble(j['total_minutes']),
    uniqueSongs: _parseInt(j['unique_songs']),
  );
}

class ReplayGenre {
  final String genre;
  final int playCount;
  final double pct;

  const ReplayGenre({
    required this.genre,
    required this.playCount,
    required this.pct,
  });

  factory ReplayGenre.fromJson(Map<String, dynamic> j) => ReplayGenre(
    genre: j['genre']?.toString() ?? '',
    playCount: _parseInt(j['play_count']),
    pct: _parseDouble(j['pct']),
  );
}

class ReplayRecentPlay {
  final String title;
  final String artist;
  final String album;
  final String playedAtIst;
  final double listenRatio;

  const ReplayRecentPlay({
    required this.title,
    required this.artist,
    required this.album,
    required this.playedAtIst,
    required this.listenRatio,
  });

  factory ReplayRecentPlay.fromJson(Map<String, dynamic> j) => ReplayRecentPlay(
    title: j['title']?.toString() ?? '',
    artist: j['artist']?.toString() ?? '',
    album: j['album']?.toString() ?? '',
    playedAtIst: j['played_at_ist']?.toString() ?? '',
    listenRatio: _parseDouble(j['listen_ratio']),
  );
}

// ---------------------------------------------------------------------------
// Monthly card (nested in YearlyReplayResponse)
// ---------------------------------------------------------------------------

class ReplayMonthlyCard {
  final int month;
  final String monthName;
  final int year;
  final int totalPlays;
  final double totalMinutes;
  final int listeningDays;
  final ReplayTrack? topTrack;
  final ReplayArtist? topArtist;
  final String? topGenre;

  const ReplayMonthlyCard({
    required this.month,
    required this.monthName,
    required this.year,
    required this.totalPlays,
    required this.totalMinutes,
    required this.listeningDays,
    this.topTrack,
    this.topArtist,
    this.topGenre,
  });

  factory ReplayMonthlyCard.fromJson(Map<String, dynamic> j) => ReplayMonthlyCard(
    month: _parseInt(j['month']),
    monthName: j['month_name']?.toString() ?? '',
    year: _parseInt(j['year']),
    totalPlays: _parseInt(j['total_plays']),
    totalMinutes: _parseDouble(j['total_minutes']),
    listeningDays: _parseInt(j['listening_days']),
    topTrack: j['top_track'] is Map
        ? ReplayTrack.fromJson(Map<String, dynamic>.from(j['top_track'] as Map))
        : null,
    topArtist: j['top_artist'] is Map
        ? ReplayArtist.fromJson(Map<String, dynamic>.from(j['top_artist'] as Map))
        : null,
    topGenre: j['top_genre']?.toString(),
  );
}

// ---------------------------------------------------------------------------
// Yearly Replay — GET /replay?year=<year>
// ---------------------------------------------------------------------------

class YearlyReplayResponse {
  final int year;
  final List<int> availableYears;
  final int totalPlays;
  final double totalMinutes;
  final int listeningDays;
  final int uniqueSongs;
  final int uniqueArtists;
  final double skipRate;
  final int peakHourIst;
  final List<ReplayTrack> topTracks;
  final List<ReplayArtist> topArtists;
  final List<ReplayGenre> topGenres;
  final Map<String, int> hourlyHeatmap;
  final List<ReplayMonthlyCard> monthlyCards;

  const YearlyReplayResponse({
    required this.year,
    required this.availableYears,
    required this.totalPlays,
    required this.totalMinutes,
    required this.listeningDays,
    required this.uniqueSongs,
    required this.uniqueArtists,
    required this.skipRate,
    required this.peakHourIst,
    required this.topTracks,
    required this.topArtists,
    required this.topGenres,
    required this.hourlyHeatmap,
    required this.monthlyCards,
  });

  factory YearlyReplayResponse.fromJson(Map<String, dynamic> j) => YearlyReplayResponse(
    year: _parseInt(j['year']),
    availableYears: (j['available_years'] as List? ?? []).map(_parseInt).toList(),
    totalPlays: _parseInt(j['total_plays']),
    totalMinutes: _parseDouble(j['total_minutes']),
    listeningDays: _parseInt(j['listening_days']),
    uniqueSongs: _parseInt(j['unique_songs']),
    uniqueArtists: _parseInt(j['unique_artists']),
    skipRate: _parseDouble(j['skip_rate']),
    peakHourIst: _parseInt(j['peak_hour_ist']),
    topTracks: _parseList(j['top_tracks'], ReplayTrack.fromJson),
    topArtists: _parseList(j['top_artists'], ReplayArtist.fromJson),
    topGenres: _parseList(j['top_genres'], ReplayGenre.fromJson),
    hourlyHeatmap: _parseHeatmap(j['hourly_heatmap']),
    monthlyCards: _parseList(j['monthly_cards'], ReplayMonthlyCard.fromJson),
  );

  /// Total listening hours formatted as "Xh Ym".
  String get totalHoursLabel {
    final h = (totalMinutes / 60).floor();
    final m = (totalMinutes % 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Skip rate as percentage string.
  String get skipRateLabel => '${(skipRate * 100).round()}%';
}

// ---------------------------------------------------------------------------
// Daily breakdown entry (monthly deep dive)
// ---------------------------------------------------------------------------

class ReplayDailyEntry {
  final String dateStr;
  final int playCount;
  final double totalMinutes;

  const ReplayDailyEntry({
    required this.dateStr,
    required this.playCount,
    required this.totalMinutes,
  });

  factory ReplayDailyEntry.fromJson(Map<String, dynamic> j) => ReplayDailyEntry(
    dateStr: j['date_str']?.toString() ?? '',
    playCount: _parseInt(j['play_count']),
    totalMinutes: _parseDouble(j['total_minutes']),
  );
}

// ---------------------------------------------------------------------------
// Monthly Replay deep dive — GET /replay/<year>/<month>
// ---------------------------------------------------------------------------

class MonthlyReplayResponse {
  final int year;
  final int month;
  final String monthName;
  final int totalPlays;
  final double totalMinutes;
  final int listeningDays;
  final int uniqueSongs;
  final int uniqueArtists;
  final double skipRate;
  final double avgListenRatio;
  final int streakDays;
  final List<ReplayTrack> topTracks;
  final List<ReplayArtist> topArtists;
  final List<ReplayGenre> topGenres;
  final Map<String, int> hourlyHeatmap;
  final List<ReplayDailyEntry> dailyBreakdown;
  final List<ReplayRecentPlay> recentPlays;

  const MonthlyReplayResponse({
    required this.year,
    required this.month,
    required this.monthName,
    required this.totalPlays,
    required this.totalMinutes,
    required this.listeningDays,
    required this.uniqueSongs,
    required this.uniqueArtists,
    required this.skipRate,
    required this.avgListenRatio,
    required this.streakDays,
    required this.topTracks,
    required this.topArtists,
    required this.topGenres,
    required this.hourlyHeatmap,
    required this.dailyBreakdown,
    required this.recentPlays,
  });

  factory MonthlyReplayResponse.fromJson(Map<String, dynamic> j) => MonthlyReplayResponse(
    year: _parseInt(j['year']),
    month: _parseInt(j['month']),
    monthName: j['month_name']?.toString() ?? '',
    totalPlays: _parseInt(j['total_plays']),
    totalMinutes: _parseDouble(j['total_minutes']),
    listeningDays: _parseInt(j['listening_days']),
    uniqueSongs: _parseInt(j['unique_songs']),
    uniqueArtists: _parseInt(j['unique_artists']),
    skipRate: _parseDouble(j['skip_rate']),
    avgListenRatio: _parseDouble(j['avg_listen_ratio']),
    streakDays: _parseInt(j['streak_days']),
    topTracks: _parseList(j['top_tracks'], ReplayTrack.fromJson),
    topArtists: _parseList(j['top_artists'], ReplayArtist.fromJson),
    topGenres: _parseList(j['top_genres'], ReplayGenre.fromJson),
    hourlyHeatmap: _parseHeatmap(j['hourly_heatmap']),
    dailyBreakdown: _parseList(j['daily_breakdown'], ReplayDailyEntry.fromJson),
    recentPlays: _parseList(j['recent_plays'], ReplayRecentPlay.fromJson),
  );

  String get totalHoursLabel {
    final h = (totalMinutes / 60).floor();
    final m = (totalMinutes % 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get skipRateLabel => '${(skipRate * 100).round()}%';
}

// ---------------------------------------------------------------------------
// Helpers (file-private)
// ---------------------------------------------------------------------------

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _parseDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

List<T> _parseList<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) {
  if (v is! List) return [];
  return v
      .whereType<Map>()
      .map((m) => fromJson(Map<String, dynamic>.from(m)))
      .toList();
}

Map<String, int> _parseHeatmap(dynamic v) {
  if (v is! Map) return {};
  return Map.fromEntries(
    v.entries.map(
      (e) => MapEntry(
        e.key.toString(),
        e.value is int ? e.value as int : int.tryParse(e.value?.toString() ?? '') ?? 0,
      ),
    ),
  );
}
