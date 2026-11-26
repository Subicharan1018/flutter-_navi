// Right-click / long-press on a chart song opens the app's full song menu.
// Its own file: the whole menu pulls in providers and Hive boxes that must not
// carry into the other trending tests.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/trending/data/trending_models.dart';
import 'package:navivibe/features/trending/logic/trending_providers.dart';
import 'package:navivibe/features/trending/ui/trending_screen.dart';
import 'package:navivibe/features/trending/ui/trending_section.dart';
import 'package:navivibe/features/trending/ui/widgets/chart_row.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import '../../helpers/test_utils.dart';
import '../../widgets/mini_player_fakes.dart' show FakePlayer, FakeSettings;

final _charts = TrendingCharts.fromJson({
  'charts': [
    {
      'key': 'tamil',
      'title': 'Tamil',
      'source': 'Test chart',
      'entries': [
        {
          'rank': 1,
          'title': 'Song 1',
          'artist': 'Artist 1',
          'song_id': 'nd1',
          'status': 'available',
        },
      ],
    },
  ],
});

class _Subsonic extends Fake implements SubsonicService {
  @override
  Future<List<Song>> getSongs(List<String> ids) async => [
    for (final id in ids) makeSong(id: id),
  ];

  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

void main() {
  testWidgets('a chart song opens the full song menu (Home and page)', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('hive_trending');
    await tester.runAsync(() async {
      Hive.init(dir.path);
      HiveBoxes.prefs = await Hive.openBox('prefs');
      HiveBoxes.auth = await Hive.openBox('auth');
      HiveBoxes.session = await Hive.openBox('session');
      HiveBoxes.audio = await Hive.openBox('audio');
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    for (final screen in <Widget>[
      const SingleChildScrollView(child: TrendingSection()),
      const TrendingScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            trendingChartsProvider.overrideWith((ref) async => _charts),
            appDatabaseProvider.overrideWithValue(db),
            subsonicServiceProvider.overrideWithValue(_Subsonic()),
            playerProvider.overrideWith((ref) => FakePlayer(false)),
            settingsProvider.overrideWith((ref) => FakeSettings()),
          ],
          child: ThemeTokens(
            tokens: AppThemeTokens.fallback,
            child: MaterialApp(home: Scaffold(body: screen)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(ChartRow).first);
      await tester.pumpAndSettle();
      for (final action in [
        'Play Next',
        'Play Last',
        'Add to Playlist…',
        'Favorite',
        'Share…',
        'Suggest Less Like This',
        'Never Recommend…',
      ]) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
