import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/replay_response.dart';
import 'package:navivibe/features/wrapped/data/wrapped_models.dart';
import 'package:navivibe/features/wrapped/data/wrapped_story.dart';

MonthlyReplayResponse _m(int month, {List<(String, int)> songs = const [], List<(String, int)> artists = const []}) => MonthlyReplayResponse(
  year: 2026, month: month, monthName: '', totalPlays: 10, totalMinutes: 10, listeningDays: 1, uniqueSongs: 1, uniqueArtists: 1,
  skipRate: 0, avgListenRatio: 1, streakDays: 0,
  topTracks: [for (final (t, p) in songs) ReplayTrack(title: t, artist: 'A', album: '', playCount: p, totalMinutes: 1, avgRatio: 1)],
  topArtists: [for (final (a, p) in artists) ReplayArtist(artist: a, playCount: p, totalMinutes: 1, uniqueSongs: 1)],
  topGenres: const [], hourlyHeatmap: const {}, dailyBreakdown: const [], recentPlays: const [],
);

WrappedSong _s(String t, int plays) => WrappedSong(title: t, artist: 'A', plays: plays, minutes: 1);

void main() {
  test('the obsession is the song with the most plays in one month', () {
    final s = buildStory(months: [_m(1, songs: [('X', 9)]), _m(2, songs: [('Y', 41), ('X', 12)])]);
    expect((s.obsession!.title, s.obsession!.plays, s.obsession!.month), ('Y', 41, 2));
  });

  test('no obsession when nothing was played more than a handful of times in a month', () {
    expect(buildStory(months: [_m(1, songs: [('X', 4)])]).obsession, isNull);
  });

  test('the race adds each month up, and keeps the leaders', () {
    final s = buildStory(months: [_m(1, artists: [('P', 10), ('Q', 5)]), _m(3, artists: [('Q', 20)])]);
    expect(s.race['P'], [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]);
    expect(s.race['Q']!.sublist(0, 4), [5, 5, 25, 25]);
  });

  test('loyalty is the artist in the most months, only when there is more than a couple', () {
    final s = buildStory(months: [for (var m = 1; m <= 6; m++) _m(m, artists: [('P', 3), if (m < 3) ('Q', 99)])]);
    expect(s.loyal!.name, 'P');
    expect(s.loyal!.months, [1, 2, 3, 4, 5, 6]);
    expect(buildStory(months: [_m(1, artists: [('P', 3)])]).loyal, isNull);
  });

  test('a comeback left the monthly lists for at least two months and returned', () {
    final s = buildStory(months: [
      _m(1, artists: [('P', 3), ('R', 9)]),
      for (var m = 2; m <= 4; m++) _m(m, artists: [('P', 3)]),
      _m(5, artists: [('P', 3), ('R', 30)]),
    ]);
    expect((s.comeback!.name, s.comeback!.gap, s.comeback!.month), ('R', 3, 5));
  });

  test('the week is the average of each weekday, Monday first', () {
    // 2026-01-05 and 2026-01-12 are Mondays, 2026-01-11 a Sunday.
    final s = buildStory(months: const [], days: const [WrappedDay(date: '2026-01-05', minutes: 10), WrappedDay(date: '2026-01-12', minutes: 30), WrappedDay(date: '2026-01-11', minutes: 5)]);
    expect(s.week, [20, 0, 0, 0, 0, 0, 5]);
  });

  group('from the library', () {
    final facts = {
      'A|A': const SongFacts(year: 1998, composer: 'Rahman', languages: ['Tamil'], mood: 'romantic'),
      'B|A': const SongFacts(year: 2020, composer: 'Anirudh', languages: ['Tamil', 'English'], mood: 'party'),
      'C|A': const SongFacts(year: 1998, composer: 'Rahman', languages: ['Hindi'], mood: 'romantic'),
    };
    final pool = [_s('A', 60), _s('B', 30), _s('C', 10), _s('Z', 99)];

    test('shares are by plays of the songs that are known, and say how many that is', () {
      final s = buildStory(months: const [], pool: pool, facts: facts);
      expect(s.known, 3);
      expect(s.languages.map((l) => (l.name, l.pct.round())), [('Tamil', 90), ('Hindi', 10)]);
      expect(s.composers.map((c) => (c.name, c.plays)), [('Rahman', 70), ('Anirudh', 30)]);
      expect(s.moods.first.name, 'romantic');
    });

    test('the music age is the play-weighted middle year, with the oldest and newest song', () {
      final s = buildStory(months: const [], pool: pool, facts: facts);
      expect((s.era!.middle, s.era!.oldest, s.era!.newest), (1998, 1998, 2020));
      expect(s.era!.newestTitle, 'B');
    });

    test('too few known songs say nothing', () {
      final s = buildStory(months: const [], pool: [_s('A', 5)], facts: facts);
      expect(s.era, isNull);
      expect(s.languages, isEmpty);
      expect(s.composers, isEmpty);
      expect(s.moods, isEmpty);
    });
  });

  test('albums add up the plays of their songs, and the number one has its tempo', () {
    final s = buildStory(
      months: const [],
      pool: [
        const WrappedSong(title: 'A', artist: 'X', plays: 50, minutes: 1, album: 'One'),
        const WrappedSong(title: 'B', artist: 'X', plays: 40, minutes: 1, album: 'Two'),
        const WrappedSong(title: 'C', artist: 'X', plays: 30, minutes: 1, album: 'Two'),
        const WrappedSong(title: 'D', artist: 'Y', plays: 5, minutes: 1),
      ],
      facts: const {'A|X': SongFacts(bpm: 96)},
    );
    expect(s.albums.map((a) => (a.name, a.plays, a.songs, a.cover)), [('Two', 70, 2, 'B|X'), ('One', 50, 1, 'A|X')]);
    expect(s.bpm, 96);
  });

  group('bookends', () {
    WrappedPlay p(String t, String at) => WrappedPlay(title: t, artist: 'A', at: at);
    test('are kept only when the neighbour proves the first is the first', () {
      final ok = bookends(2026, latest: p('L', '2026-11-20 10:00'), around: [p('F2', '2026-01-03 09:00'), p('F', '2026-01-02 09:00'), p('old', '2025-12-30 09:00')]);
      expect((ok!.first.title, ok.last.title), ('F', 'L'));
    });
    test('are dropped when the edge of the year is not in sight', () {
      expect(bookends(2026, latest: p('L', '2026-11-20 10:00'), around: [p('F2', '2026-03-03 09:00'), p('F', '2026-03-02 09:00')]), isNull);
      expect(bookends(2026, latest: null, around: const []), isNull);
    });
    test('a log that begins inside the year has a first play when it is the very end of the log', () {
      final ok = bookends(2026, latest: p('L', '2026-11-20 10:00'), around: [p('F', '2026-03-02 09:00')], reachesEnd: true);
      expect(ok!.first.title, 'F');
    });
  });

  test('json round trip keeps everything', () {
    final s = buildStory(
      months: [for (var m = 1; m <= 6; m++) _m(m, songs: [('Y', 41)], artists: [('P', 3), if (m == 1 || m == 5) ('R', 9)])],
      days: const [WrappedDay(date: '2026-01-05', minutes: 10)],
      pool: [_s('A', 60), _s('B', 30), _s('C', 10)],
      facts: {for (final k in ['A|A', 'B|A', 'C|A']) k: const SongFacts(year: 1998, composer: 'R', languages: ['Tamil'], mood: 'sad')},
      ends: const Bookends(WrappedPlay(title: 'F', artist: 'A', at: '2026-01-01'), WrappedPlay(title: 'L', artist: 'A', at: '2026-02-01')),
    );
    expect(WrappedStory.fromJson(s.toJson()).toJson(), s.toJson());
    expect(WrappedStory.fromJson(const {}).race, isEmpty);
  });
}
