import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/replay_response.dart';
import 'package:navivibe/features/wrapped/data/wrapped_models.dart';
import 'package:navivibe/features/wrapped/logic/wrapped_builder.dart';

YearlyReplayResponse _year({int plays = 1000, int songs = 300, Map<String, int>? heat, List<ReplayArtist>? artists}) =>
    YearlyReplayResponse(
      year: 2026,
      availableYears: const [2025, 2026],
      totalPlays: plays,
      totalMinutes: 5000.4,
      listeningDays: 120,
      uniqueSongs: songs,
      uniqueArtists: 80,
      skipRate: 0.2,
      peakHourIst: 23,
      topTracks: [
        for (var i = 1; i <= 6; i++) ReplayTrack(title: 'S$i', artist: 'A$i', album: 'L$i', playCount: 70 - i, totalMinutes: 200.0 - i, avgRatio: 0.9),
      ],
      topArtists: artists ?? [const ReplayArtist(artist: 'A1', playCount: 200, totalMinutes: 800, uniqueSongs: 20)],
      topGenres: const [ReplayGenre(genre: 'Tamil', playCount: 600, pct: 60), ReplayGenre(genre: 'Pop', playCount: 400, pct: 40)],
      hourlyHeatmap: heat ?? {'23': 90, '22': 40, '9': 10},
      monthlyCards: const [],
    );

MonthlyReplayResponse _month(int m, List<(String, double)> days, {String genre = 'Pop'}) => MonthlyReplayResponse(
      year: 2026,
      month: m,
      monthName: 'M$m',
      totalPlays: 50,
      totalMinutes: days.fold<double>(0, (a, d) => a + d.$2),
      listeningDays: days.length,
      uniqueSongs: 20,
      uniqueArtists: 8,
      skipRate: 0.1,
      avgListenRatio: 0.8,
      streakDays: 0,
      topTracks: [ReplayTrack(title: 'T$m', artist: 'X', album: '', playCount: 9, totalMinutes: 30, avgRatio: 1)],
      topArtists: const [],
      topGenres: [ReplayGenre(genre: genre, playCount: 10, pct: 50)],
      hourlyHeatmap: const {},
      dailyBreakdown: [for (final d in days) ReplayDailyEntry(dateStr: d.$1, playCount: 3, totalMinutes: d.$2)],
      recentPlays: const [],
    );

void main() {
  test('totals, clock and top lists come from the yearly replay', () {
    final w = buildWrapped(_year(), const []);
    expect(w.year, 2026);
    expect(w.totalMinutes, 5000);
    expect(w.peakHour, 23);
    expect(w.hourly.length, 24);
    expect(w.hourly[23], 90);
    expect(w.songs.first.title, 'S1');
    expect(w.songs.length, 5);
    expect(w.genres.first.name, 'Tamil');
  });

  test('longest streak counts consecutive days across month edges', () {
    final w = buildWrapped(_year(), [
      _month(1, [('2026-01-05', 10), ('2026-01-30', 5), ('2026-01-31', 5)]),
      _month(2, [('2026-02-01', 5), ('2026-02-02', 5), ('2026-02-10', 5)]),
    ]);
    expect(w.longestStreak, 4);
    expect(w.streakStart, '2026-01-30');
    expect(w.streakEnd, '2026-02-02');
  });

  test('no days means no streak and no biggest day', () {
    final w = buildWrapped(_year(), const []);
    expect(w.longestStreak, 0);
    expect(w.bestDay, isNull);
  });

  test('the biggest day is the day with the most minutes', () {
    final w = buildWrapped(_year(), [
      _month(3, [('2026-03-01', 20), ('2026-03-14', 190.4), ('2026-03-15', 30)]),
    ]);
    expect(w.bestDay!.date, '2026-03-14');
    expect(w.bestDay!.minutes, 190);
  });

  test('months are twelve long with the month top genre and song', () {
    final w = buildWrapped(_year(), [_month(3, [('2026-03-01', 20)], genre: 'Jazz')]);
    expect(w.months.length, 12);
    expect(w.months[2].topGenre, 'Jazz');
    expect(w.months[2].topSong, 'T3');
    expect(w.months[2].minutes, 20);
    expect(w.months[0].minutes, 0);
    expect(w.months[0].topGenre, isNull);
  });

  test('json round trip keeps everything', () {
    final w = buildWrapped(_year(), [_month(3, [('2026-03-01', 20), ('2026-03-02', 25)])]);
    final back = WrappedData.fromJson(w.toJson());
    expect(back.toJson(), w.toJson());
    expect(back.longestStreak, 2);
  });

  group('personality', () {
    test('night plays make a night owl', () {
      final w = buildWrapped(_year(heat: {'23': 90, '1': 30, '9': 5}, songs: 100), const []);
      expect(w.personality.id, 'night');
    });
    test('mostly new songs make an explorer', () {
      final w = buildWrapped(_year(plays: 1000, songs: 900, heat: {'14': 50}), const []);
      expect(w.personality.id, 'explorer');
    });
    test('one artist on repeat makes a devotee', () {
      final w = buildWrapped(
        _year(plays: 1000, songs: 100, heat: {'14': 50}, artists: const [ReplayArtist(artist: 'A1', playCount: 700, totalMinutes: 3000, uniqueSongs: 9)]),
        const [],
      );
      expect(w.personality.id, 'devotee');
    });
    test('traits stay between 0 and 1', () {
      final w = buildWrapped(_year(plays: 0, songs: 0, heat: {}), const []);
      for (final v in w.personality.traits.values) {
        expect(v, inInclusiveRange(0, 1));
      }
    });
  });
}
