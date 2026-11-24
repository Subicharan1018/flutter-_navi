import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/replay_response.dart';
import 'package:navivibe/features/wrapped/logic/wrapped_loader.dart';

class _Mem implements WrappedStore {
  final map = <String, String>{};
  @override
  String? read(String key) => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

YearlyReplayResponse _year(int y, {int plays = 100, int months = 3}) => YearlyReplayResponse(
  year: y,
  availableYears: [y],
  totalPlays: plays,
  totalMinutes: 400,
  listeningDays: 10,
  uniqueSongs: 20,
  uniqueArtists: 5,
  skipRate: 0.1,
  peakHourIst: 20,
  topTracks: const [],
  topArtists: const [],
  topGenres: const [],
  hourlyHeatmap: const {},
  monthlyCards: [
    for (var m = 1; m <= months; m++)
      ReplayMonthlyCard(
        month: m, monthName: 'M$m', year: y, totalPlays: 10, totalMinutes: 30.0 + m, listeningDays: 3, topGenre: 'G$m',
        topTrack: ReplayTrack(title: 'T$m', artist: 'A', album: '', playCount: 2, totalMinutes: 9, avgRatio: 1),
      ),
  ],
);

MonthlyReplayResponse _month(int y, int m) => MonthlyReplayResponse(
  year: y,
  month: m,
  monthName: 'M$m',
  totalPlays: 10,
  totalMinutes: 30,
  listeningDays: 1,
  uniqueSongs: 3,
  uniqueArtists: 2,
  skipRate: 0,
  avgListenRatio: 1,
  streakDays: 0,
  topTracks: const [],
  topArtists: const [],
  topGenres: const [],
  hourlyHeatmap: const {},
  dailyBreakdown: [ReplayDailyEntry(dateStr: '$y-${m.toString().padLeft(2, '0')}-01', playCount: 1, totalMinutes: 30)],
  recentPlays: const [],
);

void main() {
  late _Mem store;
  final log = <String>[];
  setUp(() {
    store = _Mem();
    log.clear();
  });

  Stream<WrappedLoad> load({
    int year = 2026,
    int current = 2026,
    Future<YearlyReplayResponse> Function(int)? fetchYear,
    Future<MonthlyReplayResponse> Function(int, int)? fetchMonth,
    Duration yearTimeout = const Duration(seconds: 2),
    Duration monthTimeout = const Duration(seconds: 2),
  }) => watchWrapped(
    year: year,
    currentYear: current,
    storeKey: 'k',
    store: store,
    fetchYear: fetchYear ?? (y) async => _year(y),
    fetchMonth: fetchMonth ?? (y, m) async => _month(y, m),
    yearTimeout: yearTimeout,
    monthTimeout: monthTimeout,
    log: log.add,
  );

  Future<YearlyReplayResponse> noYear(int _) async => throw StateError('offline');
  Future<MonthlyReplayResponse> noMonth(int _, int _) async => throw StateError('offline');

  test('the year arrives first, already with its months from the year cards', () async {
    final gate = Completer<void>();
    final events = <WrappedLoad>[];
    final sub = load(
      fetchMonth: (y, m) async {
        await gate.future;
        return _month(y, m);
      },
    ).listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events.last.settled, isFalse);
    expect(events.last.data.totalPlays, 100);
    expect(events.last.data.months[1].minutes, 32);
    expect(events.last.data.months[1].topGenre, 'G2');
    expect(events.last.data.months[1].topSong, 'T2');
    expect(events.last.total, 3);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events.last.settled, isTrue);
    expect(events.last.data.days.length, 3);
    expect(store.map, contains('k'));
    await sub.cancel();
  });

  test('months are asked side by side, never more than five at once', () async {
    var now = 0, most = 0;
    await load(
      fetchYear: (y) async => _year(y, months: 12),
      fetchMonth: (y, m) async {
        now++;
        if (now > most) most = now;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        now--;
        return _month(y, m);
      },
    ).last;
    expect(most, 5);
  });

  test('a month that hangs is given up on, and nothing is said about days that are not all known', () async {
    final last = await load(
      monthTimeout: const Duration(milliseconds: 30),
      fetchMonth: (y, m) => m == 2 ? Completer<MonthlyReplayResponse>().future : Future.value(_month(y, m)),
    ).last;
    expect(last.settled, isTrue);
    expect(last.data.days, isEmpty);
    expect(last.data.months[1].minutes, 32);
    expect(store.map, isEmpty);
  });

  test('a month that fails once is asked again', () async {
    var tries = 0;
    final last = await load(
      fetchMonth: (y, m) async {
        if (m == 2 && tries++ == 0) throw StateError('x');
        return _month(y, m);
      },
    ).last;
    expect(last.data.days.length, 3);
  });

  test('a kept copy plays at once, before the server answers, and is refreshed for next time', () async {
    await load().last;
    final gate = Completer<void>();
    final events = <WrappedLoad>[];
    final sub = load(
      fetchYear: (y) async {
        await gate.future;
        return _year(y, plays: 900);
      },
    ).listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.single.settled, isTrue);
    expect(events.single.data.totalPlays, 100);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, hasLength(1), reason: 'a film that is playing is not changed under you');
    await sub.cancel();
    expect((await load(fetchYear: noYear).first).data.totalPlays, 900);
  });

  test('leaving early still keeps the copy', () async {
    final sub = load().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(store.map, contains('k'));
  });

  test('a finished past year opens without asking', () async {
    await load(year: 2025).last;
    var asked = 0;
    final events = await load(
      year: 2025,
      fetchYear: (y) async {
        asked++;
        return _year(y);
      },
    ).toList();
    expect(events.single.data.year, 2025);
    expect(asked, 0);
  });

  test('a copy kept before the year ended is refreshed, not taken as finished', () async {
    await load().last;
    var asked = 0;
    await load(
      current: 2027,
      fetchYear: (y) async {
        asked++;
        return _year(y);
      },
    ).last;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, 1);
  });

  test('with a kept copy a dead server is not an error', () async {
    await load().last;
    expect((await load(fetchYear: noYear, fetchMonth: noMonth).toList()).single.data.totalPlays, 100);
  });

  test('with nothing kept, a failure or a hang reaches the screen', () async {
    await expectLater(load(fetchYear: noYear).toList(), throwsStateError);
    await expectLater(
      load(yearTimeout: const Duration(milliseconds: 20), fetchYear: (_) => Completer<YearlyReplayResponse>().future).toList(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a year with no plays settles empty and is not kept', () async {
    final last = await load(fetchYear: (y) async => _year(y, plays: 0)).last;
    expect((last.settled, last.data.isEmpty), (true, true));
    expect(store.map, isEmpty);
  });

  test('a damaged copy is as good as none', () async {
    store.map['k'] = '{';
    expect((await load().last).data.totalPlays, 100);
  });

  test('says where the time went, with nobody’s name in it', () async {
    await load().last;
    expect(log.any((l) => l.contains('year') && l.contains('ms')), isTrue);
    expect(log.any((l) => l.contains('month 2') && l.contains('ms')), isTrue);
    expect(log.any((l) => l.contains('build') && l.contains('ms')), isTrue);
    expect(log.any((l) => l.contains('settled') && l.contains('ms')), isTrue);
  });

  test('two servers with the same user name never share a kept copy', () {
    expect(wrappedStoreKey('https://one.example', 'subi', 2026), isNot(wrappedStoreKey('https://two.example', 'subi', 2026)));
  });
}
