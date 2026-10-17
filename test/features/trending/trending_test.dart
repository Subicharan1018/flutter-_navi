import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/trending/data/trending_api.dart';
import 'package:navivibe/features/trending/data/trending_models.dart';
import 'package:navivibe/features/trending/logic/trending_providers.dart';
import 'package:navivibe/features/trending/ui/chart_actions.dart';
import 'package:navivibe/features/trending/ui/trending_screen.dart';
import 'package:navivibe/features/trending/ui/trending_section.dart';
import 'package:navivibe/features/trending/ui/widgets/chart_row.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/ui/states.dart';

import '../../helpers/test_utils.dart';

Map<String, dynamic> _entry(int rank, {String? songId, String status = 'pending', String? movement,
        int change = 0, String? reason}) =>
    {
      'rank': rank,
      'title': 'Song $rank',
      'artist': 'Artist $rank',
      'album': 'Album',
      'cover_url': null,
      'song_id': songId,
      'status': status,
      'reason': reason,
      'movement': movement,
      'change': change,
      'previous_rank': null,
    };

Map<String, dynamic> _payload() => {
      'date': '2026-10-18',
      'charts': [
        {
          'key': 'tamil',
          'title': 'Tamil',
          'source': 'JioSaavn · Tamil: India Superhits Top 50',
          'note': null,
          'date': '2026-10-18',
          'entries': [
            _entry(2, songId: 'nd2', status: 'available', movement: 'down', change: 1),
            _entry(1, songId: 'nd1', status: 'available', movement: 'up', change: 4),
            _entry(3, status: 'lossy', movement: 'new', reason: 'Only available in lossy quality'),
            _entry(4, status: 'pending', movement: 'same'),
            _entry(5, status: 'not_found'),
          ],
        },
        {'key': 'english', 'title': 'English', 'source': 'JioSaavn', 'date': null, 'entries': []},
        {
          'key': 'tamil_nadu',
          'title': 'Tamil Nadu',
          'source': 'JioSaavn · Trending Today (Tamil)',
          'note': 'Stand-in: …',
          'date': '2026-10-17',
          'entries': [_entry(1, songId: 'nd9', status: 'available')],
        },
      ],
    };

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

void main() {
  group('parsing', () {
    final charts = TrendingCharts.fromJson(_payload());
    final tamil = charts.charts.first;

    test('charts keep the server order; entries sort by rank', () {
      expect(charts.charts.map((c) => c.key), ['tamil', 'english', 'tamil_nadu']);
      expect(tamil.entries.map((e) => e.rank), [1, 2, 3, 4, 5]);
      expect(tamil.date, DateTime(2026, 10, 18));
      expect(charts.charts[1].date, isNull);
    });

    test('movement, status and library ids', () {
      final e = tamil.entries;
      expect([for (final x in e) x.movement],
          [ChartMovement.up, ChartMovement.down, ChartMovement.isNew, ChartMovement.same, null]);
      expect(e[0].change, 4);
      expect([for (final x in e) x.status], [
        ChartSongStatus.available,
        ChartSongStatus.available,
        ChartSongStatus.lossy,
        ChartSongStatus.pending,
        ChartSongStatus.notFound,
      ]);
      expect([for (final x in e) x.playable], [true, true, false, false, false]);
      expect(tamil.playableCount, 2);
    });

    test('why a song can’t play', () {
      final e = tamil.entries;
      expect(e[0].unavailableLine, isNull);
      expect(e[2].unavailableLine, 'Only available in lossy quality');
      expect(e[3].unavailableLine, 'Downloading soon');
      expect(e[4].unavailableLine, 'Not found on the download source');
    });

    test('an empty song id is not playable; unknown status is pending', () {
      final e = ChartEntry.fromJson({'rank': 1, 'title': 't', 'artist': 'a', 'song_id': '', 'status': 'weird'});
      expect(e.playable, isFalse);
      expect(e.status, ChartSongStatus.pending);
    });

    test('empty charts are left out of the pills; pick falls back to the first', () {
      expect(charts.withSongs.map((c) => c.key), ['tamil', 'tamil_nadu']);
      expect(pickChart(charts, 'tamil_nadu')!.key, 'tamil_nadu');
      expect(pickChart(charts, 'english')!.key, 'tamil');
      expect(pickChart(charts, null)!.key, 'tamil');
      expect(pickChart(const TrendingCharts([]), null), isNull);
    });

    test('the play queue is the playable songs in rank order', () {
      final byId = {'nd1': makeSong(id: 'nd1'), 'nd2': makeSong(id: 'nd2')};
      expect(chartQueue(tamil, byId).map((s) => s.id), ['nd1', 'nd2']);
      expect(chartQueue(tamil, {'nd2': makeSong(id: 'nd2')}).map((s) => s.id), ['nd2']);
    });

    test('date line', () {
      final now = DateTime(2026, 10, 18, 9);
      expect(chartDateLine(DateTime(2026, 10, 18), now: now), 'Updated today');
      expect(chartDateLine(DateTime(2026, 10, 17), now: now), 'Updated yesterday');
      expect(chartDateLine(DateTime(2026, 10, 12), now: now), 'Updated 12 Oct');
      expect(chartDateLine(null), '');
    });
  });

  group('UI', () {
    Widget host(Widget child, Future<TrendingCharts> Function() load) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            trendingChartsProvider.overrideWith((ref) => load()),
            subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
          ],
          child: MaterialApp(
            home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: child)),
          ),
        );

    Widget section(Future<TrendingCharts> Function() load) =>
        host(const SingleChildScrollView(child: TrendingSection()), load);

    testWidgets('Home: skeleton while loading', (tester) async {
      await tester.pumpWidget(section(() => Completer<TrendingCharts>().future));
      expect(find.text('Trending'), findsOneWidget);
      expect(find.byType(TrackListSkeleton), findsOneWidget);
    });

    testWidgets('Home: error says what failed and offers a retry', (tester) async {
      await tester.pumpWidget(section(() async => throw const TrendingException('Can’t reach the server.')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Charts didn’t load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Home: nothing at all before the first snapshot', (tester) async {
      await tester.pumpWidget(section(() async => const TrendingCharts([])));
      await tester.pumpAndSettle();
      expect(find.text('Trending'), findsNothing);
    });

    testWidgets('Home: pills, ranks, movement and unavailable reasons', (tester) async {
      await tester.pumpWidget(section(() async => TrendingCharts.fromJson(_payload())));
      await tester.pumpAndSettle();
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('Tamil Nadu'), findsOneWidget);
      expect(find.text('English'), findsNothing);              // no songs yet
      expect(find.byType(ChartRow), findsNWidgets(5));          // a column of four, then rank 5 peeking in
      expect(find.text('NEW'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.arrowtriangle_up_fill), findsOneWidget);
      expect(find.text('Artist 3 · Only available in lossy quality'), findsOneWidget);
      expect(find.text('Artist 4 · Downloading soon'), findsOneWidget);

      await tester.tap(find.text('Tamil Nadu'));
      await tester.pumpAndSettle();
      expect(find.byType(ChartRow), findsOneWidget);
      expect(find.textContaining('Trending Today'), findsOneWidget);
    });

    testWidgets('tapping an unavailable song says why instead of playing', (tester) async {
      await tester.pumpWidget(section(() async => TrendingCharts.fromJson(_payload())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song 3'));
      await tester.pump();
      expect(find.text('Song 3: Only available in lossy quality'), findsOneWidget);
    });

    testWidgets('page: whole chart, library count and Play', (tester) async {
      await tester.pumpWidget(host(const TrendingScreen(), () async => TrendingCharts.fromJson(_payload())));
      await tester.pumpAndSettle();
      expect(find.text('2 of 5 in your library'), findsOneWidget);
      expect(find.byType(ChartRow), findsNWidgets(5));
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('page: empty and error states', (tester) async {
      await tester.pumpWidget(host(const TrendingScreen(), () async => const TrendingCharts([])));
      await tester.pumpAndSettle();
      expect(find.text('No charts yet'), findsOneWidget);
      await tester.pumpWidget(host(const TrendingScreen(), () async => throw const TrendingException('Nope.')));
      await tester.pumpAndSettle();
      expect(find.text('Charts didn’t load'), findsOneWidget);
      expect(find.text('Nope.'), findsOneWidget);
    });

    testWidgets('page: a stand-in chart shows its note', (tester) async {
      final container = ProviderContainer(overrides: [
        trendingChartsProvider.overrideWith((ref) async => TrendingCharts.fromJson(_payload())),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      ]);
      addTearDown(container.dispose);
      container.read(selectedChartProvider.notifier).select('tamil_nadu');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const TrendingScreen())),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Stand-in: …'), findsOneWidget);
      expect(find.textContaining('Updated'), findsOneWidget);
    });
  });
}
