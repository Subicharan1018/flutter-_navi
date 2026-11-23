/// 2.0 surfaces: the Smart Shuffle cover fan, the Replay year art, and the
/// Stats lead (hero number, tall sparkline, genre ladder). Phone 390 wide @3x.
///
///   flutter test test/goldens/redesign_v2_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/data/models/listening_stats_response.dart';
import 'package:navivibe/player/artwork.dart' show debugCoverImageOverride;
import 'package:navivibe/screens/stats/widgets/genre_mix.dart';
import 'package:navivibe/screens/stats/widgets/summary_grid.dart';
import 'package:navivibe/widgets/ui/cover_fan.dart';
import 'package:navivibe/widgets/ui/collection_art/favorites_sky.dart';
import 'package:navivibe/widgets/ui/collection_art/peak_wave.dart';
import 'package:navivibe/widgets/ui/collection_art/shuffle_trails.dart';
import 'package:navivibe/widgets/ui/year_art.dart';

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


/// Solid swatches stand in for covers, one shade per url, so the fan and the
/// ribbon show their shapes.
Future<Map<String, MemoryImage>> _swatches(List<String> keys, List<Color> colors) async {
  final out = <String, MemoryImage>{};
  for (final (i, k) in keys.indexed) {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = colors[i % colors.length]);
    final img = await rec.endRecording().toImage(16, 16);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    out[k] = MemoryImage(Uint8List.view(bytes.buffer));
  }
  return out;
}
void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => debugCoverImageOverride = null);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  testWidgets('mix fan and year art', (tester) async {
    view(tester, const Size(390, 340), 3);
    final sw = await tester.runAsync(
      () => _swatches(['a', 'b', 'c', 'd', 'e'], const [Color(0xFFB04A3C), Color(0xFF3C6FB0), Color(0xFFD9A441), Color(0xFF4E8F6A), Color(0xFF7A5FA8)]),
    );
    debugCoverImageOverride = (url, key) => sw![url]!;
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(children: [
                CoverFan(urls: const ['a', 'b', 'c', 'd'], size: 170, radius: Radii.hero, seed: 's'),
                const SizedBox(width: 16),
                YearArt(year: 2026, urls: const ['a', 'b', 'c', 'd', 'e'], size: 170, radius: Radii.hero),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                FavoritesSky(coverUrl: 'a', count: 10, size: 106, radius: Radii.hero),
                const SizedBox(width: 16),
                PeakWave(size: 106, radius: Radii.hero),
                const SizedBox(width: 16),
                ShuffleTrails(size: 106, radius: Radii.hero),
              ]),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('redesign_v2/art_phone.png'));
  });

  testWidgets('stats lead and genre ladder', (tester) async {
    view(tester, const Size(390, 760), 3);
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
      hourlyHeatmap: {'22': 40, '23': 52, '0': 31, '14': 9},
    );
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SummaryHero(
                stats: stats,
                periodPhrase: 'in the last 7 days',
                topArtist: 'Sai Abhyankkar',
                dailyPlays: [12, 30, 22, 48, 20, 35, 60, 41, 25, 52],
              ),
              GenreMixCard(
                genres: [
                  {'genre': 'Tamil Film', 'pct': 54.0},
                  {'genre': 'Indie', 'pct': 22.0},
                  {'genre': 'Soundtrack', 'pct': 12.0},
                  {'genre': 'Pop', 'pct': 8.0},
                  {'genre': 'Other', 'pct': 4.0},
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('redesign_v2/stats_phone.png'));
  });
}
