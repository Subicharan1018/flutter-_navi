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

YearlyReplayResponse _year(int y, {int plays = 100}) => YearlyReplayResponse(
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
        for (final m in [1, 2, 3])
          ReplayMonthlyCard(month: m, monthName: 'M$m', year: y, totalPlays: 10, totalMinutes: 30, listeningDays: 3),
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
      dailyBreakdown: [ReplayDailyEntry(dateStr: '$y-0$m-01', playCount: 1, totalMinutes: 30)],
      recentPlays: const [],
    );

void main() {
  test('asks for the year and each month, then keeps the result', () async {
    final store = _Mem();
    final asked = <int>[];
    final w = await loadWrapped(
      year: 2026,
      currentYear: 2026,
      storeKey: 'k',
      store: store,
      fetchYear: (y) async => _year(y),
      fetchMonth: (y, m) async {
        asked.add(m);
        return _month(y, m);
      },
    );
    expect(asked, [1, 2, 3]);
    expect(w.days.length, 3);
    expect(store.map.containsKey('k'), isTrue);
  });

  test('a finished past year opens from the device without asking', () async {
    final store = _Mem();
    await loadWrapped(
      year: 2025, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y), fetchMonth: (y, m) async => _month(y, m),
    );
    final w = await loadWrapped(
      year: 2025, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (_) => throw StateError('offline'), fetchMonth: (_, _) => throw StateError('offline'),
    );
    expect(w.year, 2025);
  });

  test('the current year falls back to the kept copy when the server is out of reach', () async {
    final store = _Mem();
    await loadWrapped(
      year: 2026, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y), fetchMonth: (y, m) async => _month(y, m),
    );
    final w = await loadWrapped(
      year: 2026, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (_) => throw StateError('offline'), fetchMonth: (_, _) => throw StateError('offline'),
    );
    expect(w.totalPlays, 100);
  });

  test('with no kept copy a failure reaches the caller', () async {
    expect(
      loadWrapped(
        year: 2026, currentYear: 2026, storeKey: 'k', store: _Mem(),
        fetchYear: (_) => throw StateError('offline'), fetchMonth: (_, _) => throw StateError('offline'),
      ),
      throwsStateError,
    );
  });

  test('a month that fails is skipped and the partial result is not kept', () async {
    final store = _Mem();
    final w = await loadWrapped(
      year: 2026, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y),
      fetchMonth: (y, m) async => m == 2 ? throw StateError('x') : _month(y, m),
    );
    expect(w.days.length, 2);
    expect(store.map, isEmpty);
  });

  test('a copy kept before the year ended is not taken for the finished year', () async {
    final store = _Mem();
    await loadWrapped(
      year: 2026, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y), fetchMonth: (y, m) async => _month(y, m),
    );
    final w = await loadWrapped(
      year: 2026, currentYear: 2027, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y, plays: 900), fetchMonth: (y, m) async => _month(y, m),
    );
    expect(w.totalPlays, 900);
  });

  test('two servers with the same user name never share a kept copy', () {
    expect(
      wrappedStoreKey('https://one.example', 'subi', 2026),
      isNot(wrappedStoreKey('https://two.example', 'subi', 2026)),
    );
  });

  test('a year with no plays is not kept', () async {
    final store = _Mem();
    final w = await loadWrapped(
      year: 2026, currentYear: 2026, storeKey: 'k', store: store,
      fetchYear: (y) async => _year(y, plays: 0), fetchMonth: (y, m) async => _month(y, m),
    );
    expect(w.isEmpty, isTrue);
    expect(store.map, isEmpty);
  });
}
