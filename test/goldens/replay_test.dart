/// Replay (year) and a month's sheet, phone 390×844 @3x and Windows 1280×800.
///
///   flutter test test/goldens/replay_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/navivibe_replay_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/replay/month_sheet.dart';
import 'package:navivibe/screens/replay/replay_screen.dart';
import 'package:navivibe/screens/replay/year_scrubber.dart';
import 'package:navivibe/screens/replay/year_shape.dart' show busiestMonth;
import 'package:navivibe/screens/replay/year_story.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

const _names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _minutes = [320.0, 410.0, 980.0, 760.0, 0.0, 540.0, 1220.0, 880.0, 300.0, 1490.0, 1010.0, 0.0];
const _artists = ['Anirudh', 'Sai Abhyankkar', 'Ilaiyaraaja', 'A. R. Rahman', 'Yuvan', 'Hiphop Tamizha'];

Map<String, dynamic> _track(String t, String a, int n) =>
    {'title': t, 'artist': a, 'album': 'Album', 'play_count': n, 'total_minutes': n * 3.4, 'avg_ratio': 0.9};

YearlyReplayResponse _year() => YearlyReplayResponse.fromJson({
      'year': 2026,
      'available_years': [2025, 2026],
      'total_plays': 3120,
      'total_minutes': 7910,
      'listening_days': 241,
      'unique_songs': 640,
      'unique_artists': 118,
      'skip_rate': 0.12,
      'peak_hour_ist': 22,
      'top_tracks': [
        for (final (i, a) in _artists.indexed) _track('Song number ${i + 1}', a, 90 - i * 11),
      ],
      'top_artists': [
        for (final (i, a) in _artists.indexed) {'artist': a, 'play_count': 400 - i * 50, 'total_minutes': 900, 'unique_songs': 20},
      ],
      'top_genres': [
        {'genre': 'Tamil Film', 'play_count': 1800, 'pct': 58},
        {'genre': 'Pop', 'play_count': 900, 'pct': 29},
      ],
      'hourly_heatmap': {for (var h = 0; h < 24; h++) '$h': (h * 7) % 40},
      'monthly_cards': [
        for (var m = 1; m <= 12; m++)
          {
            'month': m,
            'month_name': _names[m - 1],
            'year': 2026,
            'total_plays': _minutes[m - 1] == 0 ? 0 : (_minutes[m - 1] / 3).round(),
            'total_minutes': _minutes[m - 1],
            'listening_days': _minutes[m - 1] == 0 ? 0 : 18,
            if (_minutes[m - 1] > 0) 'top_track': _track('Song number ${m % 5 + 1}', _artists[m % 6], 30),
            if (_minutes[m - 1] > 0) 'top_artist': {'artist': _artists[m % 6], 'play_count': 60, 'total_minutes': 200, 'unique_songs': 9},
          },
      ],
    });

MonthlyReplayResponse _month() => MonthlyReplayResponse.fromJson({
      'year': 2026,
      'month': 10,
      'month_name': 'October',
      'total_plays': 497,
      'total_minutes': 1490,
      'listening_days': 26,
      'unique_songs': 130,
      'unique_artists': 40,
      'skip_rate': 0.1,
      'avg_listen_ratio': 0.9,
      'streak_days': 9,
      'top_tracks': [for (final (i, a) in _artists.indexed) _track('Song number ${i + 1}', a, 40 - i * 5)],
      'top_artists': [
        for (final (i, a) in _artists.indexed) {'artist': a, 'play_count': 90 - i * 10, 'total_minutes': 300, 'unique_songs': 10},
      ],
      'top_genres': [],
      'hourly_heatmap': {},
      'daily_breakdown': [
        for (var d = 1; d <= 31; d++)
          {'date': '2026-10-${d.toString().padLeft(2, '0')}', 'play_count': d % 6 == 0 ? 0 : (d * 7) % 23 + 2, 'total_minutes': 30},
      ],
      'recent_plays': [
        {'title': 'Song number 1', 'artist': 'Anirudh', 'album': 'Album', 'played_at_ist': '2026-10-30T21:41:00', 'listen_ratio': 1.0},
      ],
    });

Widget _app(Widget home) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      navivibeYearlyReplayProvider.overrideWith((ref, y) async => _year()),
      navivibeMonthlyReplayProvider.overrideWith((ref, k) async => _month()),
      songCoverIdProvider.overrideWith((ref, k) async => null),
      songCoverUrlProvider.overrideWith((ref, k) async => null),
      artistCoverUrlProvider.overrideWith((ref, k) async => null),
      allSongsProvider.overrideWith((ref) async => <Song>[]),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Builder(builder: (c) => Scaffold(backgroundColor: ThemeTokens.of(c).bgBase, body: home)),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  testWidgets('year, phone', (tester) async {
    view(tester, const Size(390, 844), 3);
    await tester.pumpWidget(_app(const ReplayScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Your Year'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/year_phone.png'));
  });

  testWidgets('year reel, phone', (tester) async {
    view(tester, const Size(390, 400), 3);
    await tester.pumpWidget(_app(SingleChildScrollView(child: YearReel(cards: _year().monthlyCards, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/reel_phone.png'));
    expect(busiestMonth(_year().monthlyCards)?.monthName, 'October');
  });

  testWidgets('month sheet, phone', (tester) async {
    view(tester, const Size(390, 844), 3);
    await tester.pumpWidget(_app(const SingleChildScrollView(child: MonthSheet(year: 2026, month: 10))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/month_phone.png'));
  });

  testWidgets('year, windows', (tester) async {
    view(tester, const Size(1280, 800), 1);
    await tester.pumpWidget(_app(const ReplayScreen()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/year_windows.png'));
  });

  testWidgets('reduced motion: reel is static and nothing animates', (tester) async {
    view(tester, const Size(390, 400), 3);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(_app(SingleChildScrollView(child: YearReel(cards: _year().monthlyCards, onOpen: (_) {}))));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the reel starts on the busiest month, swipes, and the middle poster opens', (tester) async {
    view(tester, const Size(390, 600), 3);
    ReplayMonthlyCard? opened;
    await tester.pumpWidget(_app(SingleChildScrollView(child: YearReel(cards: _year().monthlyCards, onOpen: (c) => opened = c))));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byType(YearReel)).dy;
    await tester.tapAt(Offset(40, top + 150));
    expect(opened?.month, 10); // starts on October, the busiest
    opened = null;
    await tester.dragFrom(Offset(150, top + 150), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(40, top + 150));
    expect(opened?.month, 9);
  });

  testWidgets('year story cards, finished state', (tester) async {
    view(tester, const Size(390, 844), 3);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(_app(YearStory(replay: _year())));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 5; i++) {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/story_$i.png'));
      if (i < 5) {
        await tester.tapAt(const Offset(340, 400));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('year story auto-advances with motion on', (tester) async {
    view(tester, const Size(390, 844), 3);
    await tester.pumpWidget(_app(YearStory(replay: _year())));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your song of the year'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox()); // tickers disposed cleanly
  });

  testWidgets('receipt lists the year', (tester) async {
    view(tester, const Size(390, 600), 3);
    await tester.pumpWidget(_app(SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: YearReceipt(replay: _year(), ink: Colors.white, dim: Colors.grey)))));
    await tester.pumpAndSettle();
    expect(find.text('BIGGEST MONTH'), findsOneWidget);
    expect(find.text('October'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('replay/receipt.png'));
  });
}
