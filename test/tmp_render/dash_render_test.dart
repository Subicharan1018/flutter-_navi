import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:navivibe/core/theme.dart';
import 'package:navivibe/screens/dashboard_screen.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/features/ai_shuffle/data/models/listening_stats_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/model_status_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/contribution_graph_response.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _stats = ListeningStatsResponse(
  period: 'weekly',
  label: '7 Days',
  totalPlays: 1284,
  totalMinutes: 4310,
  avgListenRatio: 0.82,
  skipRate: 0.14,
  streakDays: 6,
  topArtists: const [
    {'artist': 'Khruangbin', 'play_count': 92},
    {'artist': 'Sault', 'play_count': 71},
    {'artist': 'Yussef Dayes', 'play_count': 54},
    {'artist': 'Alfa Mist', 'play_count': 33},
    {'artist': 'Nubya Garcia', 'play_count': 21},
  ],
  topAlbums: const [],
  topTracks: const [
    {'title': 'August 10', 'artist': 'Khruangbin', 'play_count': 31, 'avg_listen_ratio': 0.94},
    {'title': 'Wildfires', 'artist': 'Sault', 'play_count': 27, 'avg_listen_ratio': 0.71},
    {'title': 'Love Is The Message', 'artist': 'Yussef Dayes', 'play_count': 19, 'avg_listen_ratio': 0.44},
    {'title': 'Organic Rust', 'artist': 'Alfa Mist', 'play_count': 12, 'avg_listen_ratio': 0.88},
    {'title': 'Source', 'artist': 'Nubya Garcia', 'play_count': 8, 'avg_listen_ratio': 0.62},
  ],
  recentPlays: const [],
  genreBreakdown: const [
    {'genre': 'Psych soul', 'pct': 34.0},
    {'genre': 'Spiritual jazz', 'pct': 26.0},
    {'genre': 'Broken beat', 'pct': 18.0},
    {'genre': 'Ambient', 'pct': 12.0},
    {'genre': 'Dub', 'pct': 10.0},
  ],
  hourlyHeatmap: {for (var h = 0; h < 24; h++) '$h': (h > 7 && h < 23) ? (h * 7) % 41 + 3 : 1},
);

const _model = ModelStatusResponse(
  username: 'subi',
  builtAt: '2026-08-20T10:00:00Z',
  totalPlaysProcessed: 8421,
  songsInLibrary: 3190,
  composersTracked: 412,
  contextBuckets: 24,
  unprocessedEvents: 180,
  modelSizeMb: 4.7,
  rebuildThreshold: 500,
  songsWithPairings: 1200,
  starterContexts: 9,
);

void main() {
  final days = List.generate(120, (i) {
    final d = DateTime.now().subtract(Duration(days: 119 - i));
    // one gap 4 days back, so the streak run visibly breaks
    final count = (119 - i) == 4 ? 0 : (i % 9) * 3;
    return ContributionDay(date: _iso(d), count: count);
  });

  for (final entry in {
    'spotify': AppThemeMode.spotify,
    'zen': AppThemeMode.zen,
    'analog': AppThemeMode.analog,
    'frost': AppThemeMode.frost,
  }.entries) {
    testWidgets('render ${entry.key}', (tester) async {
      final tokens = ThemeVariants.of(entry.value);
      tester.view.physicalSize = const Size(800, 4800);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listeningStatsProvider('weekly').overrideWith((ref) async => _stats),
            modelStatusProvider.overrideWith((ref) async => _model),
            contributionGraphProvider.overrideWith(
                (ref) async => ContributionGraphResponse(days: days)),
            songCoverUrlProvider.overrideWith((ref, k) async => null),
            artistCoverUrlProvider.overrideWith((ref, k) async => null),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: (entry.value == AppThemeMode.spotify || entry.value == AppThemeMode.aura || entry.value == AppThemeMode.frost) ? Brightness.dark : Brightness.light),
            home: RepaintBoundary(
              key: boundaryKey,
              child: ThemeTokens(tokens: tokens, child: const DashboardScreen()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final scratchDir = Platform.environment['SCRATCH'];
      if (scratchDir != null) {
        final boundary = boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null) {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ImageByteFormat.png);
          if (bytes != null) {
            File('$scratchDir/dash_${entry.key}.png')
                .writeAsBytesSync(bytes.buffer.asUint8List());
          }
        }
      }
    });
  }
}
