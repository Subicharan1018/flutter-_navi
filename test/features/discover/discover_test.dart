import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/discover/logic/discover_providers.dart';
import 'package:navivibe/features/discover/ui/discover_section.dart';
import 'package:navivibe/features/trending/data/trending_models.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/ui/media.dart';
import 'package:navivibe/widgets/ui/states.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

const _arrivals = [
  ChartArrival(songId: 'a1', title: 'Patient Zero', artist: 'Taylor Swift', charts: ['Hot 100', 'Global 200']),
  ChartArrival(songId: 'a2', title: 'Pesamale', artist: 'Siri Xander', charts: ['Tamil']),
  ChartArrival(songId: 'a3', title: 'Orphan', artist: 'Someone'),
];

List<DiscoverItem> _items() => mergeDiscover(_arrivals, [
      (id: 'u1', title: 'Old Gem', artist: 'Ilaiyaraaja'),
      (id: 'a2', title: 'Pesamale', artist: 'Siri Xander'),          // already in: no twice
      (id: '', title: 'No id', artist: 'x'),                          // not in the library: skipped
    ]);

void main() {
  group('merge', () {
    test('chart arrivals first, then never played, no song twice', () {
      final items = _items();
      expect(items.map((i) => i.songId), ['a1', 'a2', 'a3', 'u1']);
      expect(items.map((i) => i.reason), ['New · Hot 100', 'New · Tamil', 'New', 'Never played']);
      expect(items.map((i) => i.fromCharts), [true, true, true, false]);
    });

    test('caps: at most maxNew arrivals and max in all', () {
      final many = [for (var i = 0; i < 20; i++) ChartArrival(songId: 'a$i', title: 't', artist: 'a')];
      final unplayed = [for (var i = 0; i < 20; i++) (id: 'u$i', title: 't', artist: 'a')];
      final items = mergeDiscover(many, unplayed, maxNew: 5, max: 8);
      expect(items.where((i) => i.fromCharts).length, 5);
      expect(items.length, 8);
    });

    test('arrival parsing', () {
      final a = ChartArrival.fromJson({
        'song_id': 'x', 'title': 'T', 'artist': 'A', 'added_at': 1760000000.5, 'charts': ['Hot 100'],
      });
      expect(a.addedAt, DateTime.fromMillisecondsSinceEpoch(1760000000500));
      expect(a.charts, ['Hot 100']);
    });
  });

  group('UI', () {
    Widget host(Future<List<DiscoverItem>> Function() load) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            discoverProvider.overrideWith((ref) => load()),
            subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ThemeTokens(
                tokens: AppThemeTokens.fallback,
                child: const SingleChildScrollView(child: DiscoverSection()),
              ),
            ),
          ),
        );

    testWidgets('loading: header and cover-shaped placeholders', (tester) async {
      await tester.pumpWidget(host(() => Completer<List<DiscoverItem>>().future));
      expect(find.text('New in Your Library'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text('Play'), findsNothing);
    });

    testWidgets('error: says so with Try again', (tester) async {
      await tester.pumpWidget(host(() async => throw Exception('offline')));
      await tester.pumpAndSettle();
      expect(find.textContaining('New songs didn’t load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('nothing new: the shelf is gone', (tester) async {
      await tester.pumpWidget(host(() async => const []));
      await tester.pumpAndSettle();
      expect(find.text('New in Your Library'), findsNothing);
    });

    testWidgets('data: big covers, reasons, counts, Play and Shuffle', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(() async => _items()));
      await tester.pumpAndSettle();
      expect(find.text('3 new from the charts · 1 never played'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Taylor Swift · New · Hot 100'), findsOneWidget);
      final card = tester.widget<MediaCard>(find.byType(MediaCard).first);
      expect(card.size, closeTo(390 * 0.56, 0.01));                  // bigger than a shelf's 164
    });
  });
}
