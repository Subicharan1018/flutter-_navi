import 'dart:async';

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
import 'package:navivibe/features/trending/ui/widgets/chart_details.dart';
import 'package:navivibe/features/trending/ui/widgets/chart_row.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
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

Map<String, dynamic> _billboardPayload() => {
      'charts': [
        {
          'key': 'billboard_hot_100',
          'title': 'Hot 100',
          'source': 'Billboard · Hot 100 (US, weekly)',
          'kind': 'billboard',
          'date': '2026-10-18',
          'week_of': 'October 17, 2026',
          'description': 'The week’s most popular current songs.',
          'entries': [
            {
              ..._entry(1, songId: 'nd1', status: 'available', movement: 'same'),
              'title': 'Patient Zero',
              'previous_rank': 1,
              'details': {
                'billboard': {
                  'status': null, 'last_week': 1, 'peak': 1, 'weeks_on_chart': 2, 'weeks_at_no1': 2,
                  'debut_position': 1, 'debut_date': '10/10/26', 'peak_position': 1, 'peak_date': '10/10/26',
                  'awards': [], 'songwriters': ['T.Swift', 'Max Martin'], 'producers': ['Shellback'],
                  'label': 'Republic',
                },
              },
            },
            {
              ..._entry(2, movement: 'reentry'),
              'title': 'Back Again',
              'details': {
                'billboard': {'status': 're-entry', 'last_week': null, 'peak': 9, 'weeks_on_chart': 4,
                  'awards': ['Gains In Performance']},
              },
            },
          ],
        },
        {
          'key': 'india',
          'title': 'India',
          'source': 'JioSaavn · India Superhits Top 50',
          'kind': 'saavn',
          'date': '2026-10-18',
          'entries': [
            {
              ..._entry(1, songId: 'nd5', status: 'available'),
              'title': 'Yeshanagula',
              'details': {
                'saavn': {
                  'play_count': 6739865, 'year': 2026, 'release_date': '2026-08-29', 'language': 'Telugu',
                  'label': 'SaReGaMA India Ltd', 'album': 'Yeshanagula', 'duration_s': 188, 'explicit': false,
                  'music': ['Anirudh Ravichander'], 'lyricists': ['Kasarla Shyam'], 'singers': [],
                  'copyright': '℗ 2026 Saregama India Ltd', 'has_lyrics': false,
                },
              },
            },
          ],
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

    test('Billboard and JioSaavn details', () {
      final c = TrendingCharts.fromJson(_billboardPayload()).charts;
      final hot = c[0];
      expect(hot.kind, ChartKind.billboard);
      expect(hot.weekOf, 'October 17, 2026');
      final bb = hot.entries[0].billboard!;
      expect([bb.lastWeek, bb.peak, bb.weeksOnChart, bb.weeksAtNo1, bb.debutPosition], [1, 1, 2, 2, 1]);
      expect(bb.songwriters, ['T.Swift', 'Max Martin']);
      expect(hot.entries[1].movement, ChartMovement.reentry);
      expect(chartStatsLine(hot.entries[0]), 'LW 1 · Peak 1 · 2 wks');
      expect(chartStatsLine(hot.entries[1]), 'LW – · Peak 9 · 4 wks');
      expect(ChartBadges.labels(hot.entries[0]), ['No. 1 · 2 wks']);
      expect(ChartBadges.labels(hot.entries[1]), ['Gains In Performance']);

      final india = c[1];
      expect(india.kind, ChartKind.saavn);
      final sv = india.entries[0].saavn!;
      expect(sv.playCount, 6739865);
      expect(sv.releaseDate, DateTime(2026, 8, 29));
      expect(chartStatsLine(india.entries[0]), '6.7M plays · Telugu · 2026');
      final facts = Map.fromEntries(ChartDetailsPanel.facts(india.entries[0]).map((f) => MapEntry(f.$1, f.$2)));
      expect(facts['Plays'], '6,739,865');
      expect(facts['Released'], '29 Aug 2026');
      expect(facts['Length'], '3:08');
      expect(facts['Lyrics'], 'Kasarla Shyam');
      expect(facts.containsKey('Explicit'), isFalse);
    });

    test('a row without details has no stats', () {
      final e = TrendingCharts.fromJson(_payload()).charts.first.entries.first;
      expect(e.hasDetails, isFalse);
      expect(chartStatsLine(e), isNull);
      expect(ChartDetailsPanel.facts(e), isEmpty);
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
      expect(find.byWidgetPredicate((w) => w is NaviIcon && w.glyph == NaviGlyph.caretUp), findsOneWidget);
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

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('page, wide: Billboard LW · PEAK · WKS columns instead of the stats line', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const TrendingScreen(), () async => TrendingCharts.fromJson(_billboardPayload())));
      await tester.pumpAndSettle();
      expect(find.text('LW'), findsOneWidget);
      expect(find.text('PEAK'), findsOneWidget);
      expect(find.text('WKS'), findsOneWidget);
      expect(find.byType(BillboardColumns), findsNWidgets(3));         // header + 2 rows
      expect(find.text('LW 1 · Peak 1 · 2 wks'), findsNothing);
    });

    testWidgets('page: Billboard week, stats, chips, RE marker; a tap opens the details', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const TrendingScreen(), () async => TrendingCharts.fromJson(_billboardPayload())));
      await tester.pumpAndSettle();
      expect(find.text('Week of October 17, 2026'), findsOneWidget);
      expect(find.text('The week’s most popular current songs.'), findsOneWidget);
      expect(find.text('LW 1 · Peak 1 · 2 wks'), findsOneWidget);
      expect(find.text('No. 1 · 2 wks'), findsOneWidget);
      expect(find.text('Gains In Performance'), findsOneWidget);
      expect(find.text('RE'), findsOneWidget);
      expect(find.text('Songwriters'), findsNothing);

      await tester.tap(find.text('Patient Zero'));
      await tester.pumpAndSettle();
      expect(find.text('Songwriters'), findsOneWidget);
      expect(find.text('T.Swift, Max Martin'), findsOneWidget);
      expect(find.text('No. 1 · 10/10/26'), findsNWidgets(2));       // debut and peak
      expect(find.text('Play'), findsNWidgets(2));                     // header + the open row

      await tester.tap(find.text('Patient Zero'));
      await tester.pumpAndSettle();
      expect(find.text('Songwriters'), findsNothing);
    });

    testWidgets('page: JioSaavn details open the same way', (tester) async {
      phone(tester);
      final container = ProviderContainer(overrides: [
        trendingChartsProvider.overrideWith((ref) async => TrendingCharts.fromJson(_billboardPayload())),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      ]);
      addTearDown(container.dispose);
      container.read(selectedChartProvider.notifier).select('india');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const TrendingScreen())),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('6.7M plays · Telugu · 2026'), findsOneWidget);
      await tester.tap(find.text('Yeshanagula'));
      await tester.pumpAndSettle();
      expect(find.text('29 Aug 2026'), findsOneWidget);
      expect(find.text('SaReGaMA India Ltd'), findsOneWidget);
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
