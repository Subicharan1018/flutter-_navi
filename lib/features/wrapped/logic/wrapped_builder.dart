import '../../ai_shuffle/data/models/replay_response.dart';
import '../data/wrapped_models.dart';

/// Works out the whole Wrapped from the year's replay and the replays of its months (those with plays).
/// Pure: no network, no clock, so it is the same on every run.
WrappedData buildWrapped(YearlyReplayResponse y, List<MonthlyReplayResponse> months) {
  final hourly = List<int>.filled(24, 0);
  y.hourlyHeatmap.forEach((k, v) {
    final h = int.tryParse(k);
    if (h != null && h >= 0 && h < 24) hourly[h] = v;
  });

  final byMonth = {for (final m in months) m.month: m};
  final dayMinutes = <String, double>{};
  for (final m in months) {
    for (final d in m.dailyBreakdown) {
      if (d.dateStr.isEmpty || d.totalMinutes <= 0) continue;
      dayMinutes[d.dateStr] = (dayMinutes[d.dateStr] ?? 0) + d.totalMinutes;
    }
  }
  final dates = dayMinutes.keys.toList()..sort();
  final days = [for (final d in dates) WrappedDay(date: d, minutes: dayMinutes[d]!.round())];

  // Longest run of consecutive calendar days.
  var best = 0;
  String? bestStart;
  String? bestEnd;
  DateTime? runStart;
  DateTime? prev;
  for (final d in dates) {
    final t = DateTime.tryParse(d);
    if (t == null) continue;
    final day = DateTime.utc(t.year, t.month, t.day);
    if (prev != null && day.difference(prev).inDays == 1) {
      // run continues
    } else {
      runStart = day;
    }
    prev = day;
    final len = day.difference(runStart!).inDays + 1;
    if (len > best) {
      best = len;
      bestStart = _iso(runStart);
      bestEnd = _iso(day);
    }
  }

  WrappedDay? bestDay;
  for (final d in days) {
    if (bestDay == null || d.minutes > bestDay.minutes) bestDay = d;
  }

  return WrappedData(
    year: y.year,
    totalMinutes: y.totalMinutes.round(),
    totalPlays: y.totalPlays,
    uniqueSongs: y.uniqueSongs,
    uniqueArtists: y.uniqueArtists,
    listeningDays: y.listeningDays,
    skipRate: y.skipRate,
    peakHour: y.peakHourIst,
    hourly: hourly,
    songs: [for (final t in y.topTracks.take(5)) WrappedSong(title: t.title, artist: t.artist, plays: t.playCount, minutes: t.totalMinutes.round())],
    artists: [for (final a in y.topArtists.take(6)) WrappedArtist(name: a.artist, plays: a.playCount, minutes: a.totalMinutes.round(), songs: a.uniqueSongs)],
    genres: [for (final g in y.topGenres.take(6)) WrappedGenre(name: g.genre, pct: g.pct)],
    months: [
      for (var m = 1; m <= 12; m++)
        WrappedMonth(
          month: m,
          minutes: byMonth[m]?.totalMinutes.round() ?? 0,
          topGenre: byMonth[m]?.topGenres.firstOrNull?.genre,
          topSong: byMonth[m]?.topTracks.firstOrNull?.title,
        ),
    ],
    days: days,
    longestStreak: best,
    streakStart: bestStart,
    streakEnd: bestEnd,
    bestDay: bestDay,
  );
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
