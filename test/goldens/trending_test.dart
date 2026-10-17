/// Trending page and Home's Trending shelf at phone size (390×844 @3x).
///
///   flutter test test/goldens/trending_test.dart --update-goldens
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/trending/data/trending_models.dart';
import 'package:navivibe/features/trending/logic/trending_providers.dart';
import 'package:navivibe/features/trending/ui/trending_screen.dart';
import 'package:navivibe/features/trending/ui/trending_section.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

const _songs = [
  ('Radhimaa (From "Think Indie")', 'Sai Abhyankkar, Nargis Teji', 'nd1', 'available', 'up', 2),
  ('Raga of Revenge', 'Anirudh Ravichander', 'nd2', 'available', 'down', 1),
  ('Pesamale', 'Siri Xander', null, 'pending', 'new', 0),
  ('Ooroda Oththa Don', 'Sai Abhyankkar', 'nd4', 'available', 'same', 0),
  ('Rathinamo (Female Version)', 'Saurav Srisan', null, 'lossy', 'up', 6),
  ('Pavazha Malli (From "Think Indie")', 'Vivek', 'nd6', 'available', 'down', 3),
  ('One Name', 'Anirudh Ravichander', 'nd7', 'available', 'same', 0),
  ('Hangova', 'Anirudh Ravichander', 'nd8', 'available', 'up', 1),
  ('God Mode', 'Anirudh Ravichander', null, 'not_found', 'new', 0),
  ('Magale', 'Sai Abhyankkar', 'nd10', 'available', 'down', 4),
];

TrendingCharts _charts() => TrendingCharts.fromJson({
      'charts': [
        for (final (key, title) in [
          ('tamil', 'Tamil'),
          ('english', 'English'),
          ('hindi', 'Hindi'),
          ('malayalam', 'Malayalam'),
          ('worldwide', 'Worldwide'),
          ('india', 'India'),
          ('tamil_nadu', 'Tamil Nadu'),
        ])
          {
            'key': key,
            'title': title,
            'source': 'JioSaavn · Tamil: India Superhits Top 50',
            'date': DateTime.now().toIso8601String().substring(0, 10),
            'entries': [
              for (final (i, s) in _songs.indexed)
                {
                  'rank': i + 1,
                  'title': s.$1,
                  'artist': s.$2,
                  'song_id': s.$3,
                  'status': s.$4,
                  'movement': s.$5,
                  'change': s.$6,
                  'reason': s.$4 == 'lossy' ? 'Only available in lossy quality' : null,
                },
            ],
          },
      ],
    });

Map<String, dynamic> _bb(int? lw, int peak, int wks,
        {String? status, int? no1, List<String> awards = const [], String label = 'Republic'}) =>
    {
      'billboard': {
        'status': status, 'last_week': lw, 'peak': peak, 'weeks_on_chart': wks, 'weeks_at_no1': no1,
        'debut_position': peak, 'debut_date': '10/10/26', 'peak_position': peak, 'peak_date': '10/10/26',
        'awards': awards, 'songwriters': ['T.Swift', 'Max Martin', 'Shellback'],
        'producers': ['Max Martin', 'Shellback', 'T.Swift'], 'label': label,
      },
    };

TrendingCharts _billboard() => TrendingCharts.fromJson({
      'charts': [
        {
          'key': 'billboard_hot_100',
          'title': 'Hot 100',
          'source': 'Billboard · Hot 100 (US, weekly)',
          'kind': 'billboard',
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'week_of': 'October 17, 2026',
          'description': 'The week’s most popular current songs across all genres, ranked by streaming, '
              'radio airplay and sales data as compiled by Luminate.',
          'entries': [
            for (final (i, s) in [
              ('Patient Zero', 'Taylor Swift', 'nd1', 'same', 0, _bb(1, 1, 2, no1: 2)),
              ("Choosin' Texas", 'Ella Langley', null, 'same', 0, _bb(2, 1, 51, no1: 24)),
              ('Boston', 'Stella Lefty', 'nd3', 'up', 3, _bb(6, 2, 27)),
              ('Been By Now', 'Morgan Wallen', null, 'down', 1, _bb(3, 3, 12)),
              ('Solar Eclipse', 'Drake, Don Toliver', null, 'new', 0,
                  _bb(null, 5, 1, status: 'new', awards: ['Highest ranking debut', 'Gains In Performance'])),
              ('Dracula', 'Tame Impala, JENNIE', 'nd6', 'reentry', 0, _bb(null, 6, 9, status: 're-entry')),
            ].indexed)
              {
                'rank': i + 1, 'title': s.$1, 'artist': s.$2, 'song_id': s.$3,
                'status': s.$3 == null ? 'pending' : 'available', 'movement': s.$4, 'change': s.$5,
                'details': s.$6,
              },
          ],
        },
      ],
    });

Widget _app(Widget home) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      trendingChartsProvider.overrideWith((ref) async => _charts()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('trending page', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const TrendingScreen()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('trending/page.png'));
  });

  testWidgets('billboard page, first row open', (tester) async {
    await phone(tester);
    final container = ProviderContainer(overrides: [
      trendingChartsProvider.overrideWith((ref) async => _billboard()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    ]);
    addTearDown(container.dispose);
    final tokens = AppThemeTokens.fallback;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ThemeTokens(
        tokens: tokens,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: const TrendingScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Patient Zero'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('trending/billboard_open.png'));
  });

  testWidgets('home trending shelf', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: const SafeArea(child: SingleChildScrollView(child: TrendingSection())),
      ),
    )));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('trending/home_shelf.png'));
  });
}
