// Stats must never show one period's numbers under another period's name, and
// the streak comes from the listening history, not from one period's slice.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/data/models/contribution_graph_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/listening_stats_response.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/screens/stats/stats_screen.dart';
import 'package:navivibe/screens/stats/widgets/streak_ticket.dart';
import 'package:navivibe/utils/format.dart';
import 'package:navivibe/utils/platform_utils.dart';

ListeningStatsResponse _stats(int plays) => ListeningStatsResponse.fromJson({
  'total_plays': plays,
  'total_minutes': plays * 3,
  'streak_days': 0,
});

ContributionDay _day(int daysAgo, int count) => ContributionDay(
  date: isoDate(DateTime.now().subtract(Duration(days: daysAgo))),
  count: count,
);

void main() {
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  group('streak', () {
    final now = DateTime(2026, 11, 26, 0, 30);
    ContributionDay on(int d) => ContributionDay(
      date: '2026-11-${d.toString().padLeft(2, '0')}',
      count: 3,
    );

    test('yesterday keeps it alive before the first play of today', () {
      expect(listeningStreak([on(23), on(24), on(25)], now), 3);
    });

    test('today extends it', () {
      expect(listeningStreak([on(24), on(25), on(26)], now), 3);
    });

    test('a missed day ends it', () {
      expect(listeningStreak([on(22), on(23), on(24)], now), 0);
      expect(listeningStreak([on(22), on(24), on(25)], now), 2);
      expect(listeningStreak(const [], now), 0);
    });
  });

  Future<void> pump(
    WidgetTester tester,
    Future<ListeningStatsResponse> Function(String period) load, {
    List<ContributionDay> days = const [],
  }) async {
    PlatformUtils.debugDesktopOverride = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => const Duration(seconds: 30),
        overrides: [
          listeningStatsProvider.overrideWith((ref, period) => load(period)),
          contributionGraphProvider.overrideWith(
            (ref) async => ContributionGraphResponse(days: days),
          ),
          modelStatusProvider.overrideWith((ref) => Completer<Never>().future),
          artistCoverUrlProvider.overrideWith((ref, name) async => null),
        ],
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            theme: AppTheme.build(AppThemeTokens.fallback),
            home: const StatsScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('while All Time loads, the week’s numbers keep the week’s name', (
    tester,
  ) async {
    final all = Completer<ListeningStatsResponse>();
    await pump(
      tester,
      (p) => p == 'all' ? all.future : Future.value(_stats(255)),
    );
    expect(find.text('listened this week'), findsOneWidget);

    await tester.tap(find.text('All Time'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('listened all time'), findsNothing);
    expect(find.text('listened this week'), findsOneWidget);
    expect(find.text('Loading All Time…'), findsOneWidget);

    all.complete(_stats(9000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('listened all time'), findsOneWidget);
    expect(find.text('Loading All Time…'), findsNothing);
  });

  testWidgets('a failed All Time says so instead of showing the week', (
    tester,
  ) async {
    await pump(
      tester,
      (p) async => p == 'all' ? throw Exception('timeout') : _stats(255),
    );
    await tester.tap(find.text('All Time'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('listened all time'), findsNothing);
    expect(find.text('listened this week'), findsNothing);
    expect(find.text('Stats aren’t available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 10));
  });

  testWidgets('the ticket reads the history, not the server’s period slice', (
    tester,
  ) async {
    await pump(
      tester,
      (p) async => _stats(255), // the server says streak 0
      days: [_day(1, 59), _day(2, 111), _day(3, 81), _day(5, 28)],
    );
    expect(tester.widget<StreakTicket>(find.byType(StreakTicket)).streak, 3);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
