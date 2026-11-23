/// 2.0 surfaces: the art tiles (Smart Shuffle mix, Replay year, Favorites,
/// Highlights, Start Listening) drawn from textured stand-in covers, and the
/// Stats cards (hero, streak ticket, dial plate, genre poster, model drop).
/// Phone 390 wide.
///
///   flutter test test/goldens/redesign_v2_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/data/models/listening_stats_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/model_status_response.dart';
import 'package:navivibe/player/artwork.dart' show debugCoverImageOverride;
import 'package:navivibe/screens/stats/widgets/genre_mix.dart';
import 'package:navivibe/screens/stats/widgets/hours_chart.dart';
import 'package:navivibe/screens/stats/widgets/model_status.dart';
import 'package:navivibe/screens/stats/widgets/summary_grid.dart';
import 'package:navivibe/widgets/ui/collection_art/favorites_stack.dart';
import 'package:navivibe/widgets/ui/collection_art/mix_flow.dart';
import 'package:navivibe/widgets/ui/collection_art/peak_wave.dart';
import 'package:navivibe/widgets/ui/collection_art/shuffle_trails.dart';
import 'package:navivibe/widgets/ui/collection_art/year_poster.dart';

import 'fake_covers.dart';
import 'golden_fonts.dart';

Widget _app(Widget body) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Scaffold(backgroundColor: tokens.bgBase, body: body),
      ),
    ),
  );
}

const _ids = ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8'];

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => debugCoverImageOverride = null);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> covers(WidgetTester tester) async {
    final sw = await tester.runAsync(() => texturedCovers());
    debugCoverImageOverride = (url, key) => sw![url]!;
  }


  testWidgets('art tiles: mix flow and year poster', (tester) async {
    view(tester, const Size(390, 220), 3);
    await covers(tester);
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              MixFlow(urls: _ids, size: 170, radius: Radii.hero, seed: 's'),
              const SizedBox(width: 16),
              YearPoster(year: 2026, urls: _ids.sublist(3), size: 170, radius: Radii.hero),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('redesign_v2/art_phone.png'));
  });

  testWidgets('art tiles: constellation, peaks, crossing covers', (tester) async {
    view(tester, const Size(390, 330), 3);
    await covers(tester);
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FavoritesStack(urls: _ids, size: 106, radius: Radii.hero),
              const SizedBox(width: 16),
              PeakWave(coverUrl: _ids[2], size: 106, radius: Radii.hero),
              const SizedBox(width: 16),
              ShuffleTrails(urls: _ids.sublist(4), size: 106, radius: Radii.hero),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('redesign_v2/art_small_phone.png'));
  });

  testWidgets('stats cards', (tester) async {
    view(tester, const Size(390, 1900), 2);
    await covers(tester);
    const stats = ListeningStatsResponse(
      period: 'weekly',
      label: '7 Days',
      totalPlays: 312,
      totalMinutes: 1243,
      avgListenRatio: 0.8,
      skipRate: 0.18,
      streakDays: 12,
      topArtists: [],
      topAlbums: [],
      topTracks: [],
      recentPlays: [],
      genreBreakdown: [],
      hourlyHeatmap: {'22': 40, '23': 52, '0': 31, '14': 9, '9': 12},
    );
    final model = ModelStatusResponse.fromJson(const {
      'total_plays_processed': 5120,
      'songs_in_library': 2400,
      'context_buckets': 84,
      'unprocessed_events': 18,
      'rebuild_threshold': 50,
    });
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SummaryHero(
                stats: stats,
                periodPhrase: 'in the last 7 days',
                topArtist: 'Sai Abhyankkar',
                topArtistCover: 'c4',
                dailyPlays: [12, 30, 22, 48, 20, 35, 60, 41, 25, 52],
              ),
              const ListeningClock(byHour: {'22': 40, '23': 52, '0': 31, '14': 9, '9': 12}),
              const GenreMixCard(
                genres: [
                  {'genre': 'Tamil Film', 'pct': 54.0},
                  {'genre': 'Indie', 'pct': 22.0},
                  {'genre': 'Soundtrack', 'pct': 12.0},
                  {'genre': 'Pop', 'pct': 8.0},
                  {'genre': 'Other', 'pct': 4.0},
                ],
              ),
              ModelStatusCard(status: model),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('redesign_v2/stats_phone.png'));
  });
}
