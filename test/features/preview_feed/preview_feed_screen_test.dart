import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart'
    show OnlineFetchException;
import 'package:navivibe/features/preview_feed/ui/preview_feed_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';

import 'preview_feed_fakes.dart';

Widget app(FeedHarness h, {bool reduceMotion = false}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: h.overrides.cast<Override>(),
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        theme: AppTheme.build(tokens),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const PreviewFeedScreen(),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  // The fade between clips and the page tint run for a few hundred ms; the waveform ticker never settles on its own.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

FeedHarness harness({int n = 5}) => FeedHarness([
  [for (var i = 1; i <= n; i++) previewItem(i)],
]);

void main() {
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PlatformUtils.debugTvOverride = null;
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PlatformUtils.debugDesktopOverride = false;
  }

  testWidgets(
    'phone: the first song, its reason and the hearts left show; its clip plays on the feed audio',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Artist 1'), findsOneWidget);
      expect(find.text('Trending · tamil #1'), findsOneWidget);
      expect(find.text('5 hearts left today'), findsOneWidget);
      expect(find.text('Swipe up for the next song'), findsOneWidget);
      expect(h.audio.calls, ['play https://cdn.example/p1.mp3']);
      expect(h.mainCalls, ['pause']);
    },
  );

  testWidgets(
    'phone: swiping up shows the next song, plays its clip and counts the first as a no',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await settle(tester);
      expect(find.text('Song 2'), findsOneWidget);
      expect(h.api.signals, ['no pv_1']);
      expect(h.audio.calls.last, 'play https://cdn.example/p2.mp3');
      expect(
        find.text('Swipe up for the next song'),
        findsNothing,
      ); // the hint has done its job
    },
  );

  testWidgets(
    'phone: the heart fills, fetches, and is not undone by swiping on',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Heart to fetch this song'));
      await settle(tester);
      expect(h.api.signals, ['yes pv_1']);
      expect(h.fetched, ['pv_1']);
      expect(
        find.bySemanticsLabel('Hearted. Fetching this song'),
        findsOneWidget,
      );
      expect(find.text('Fetching Song 1'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await settle(tester);
      expect(h.api.signals, ['yes pv_1']);
      expect(find.text('4 hearts left today'), findsOneWidget);
    },
  );

  testWidgets(
    'phone: a double tap hearts too; a single tap pauses the feed audio only',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      await tester.tapAt(const Offset(195, 300));
      await tester.pump(const Duration(milliseconds: 450));
      expect(h.audio.calls.last, 'pause');
      expect(h.mainCalls, [
        'pause',
      ]); // only the polite pause when the feed opened
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(195, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(195, 300));
      await settle(tester);
      expect(h.api.signals, contains('yes pv_1'));
    },
  );

  testWidgets('phone: the daily cap is a sentence, not an error', (
    tester,
  ) async {
    phone(tester);
    final h = harness();
    h.api.capped = true;
    await tester.pumpWidget(app(h));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Heart to fetch this song'));
    await settle(tester);
    expect(find.textContaining('today’s limit of hearts'), findsOneWidget);
    expect(h.fetched, isEmpty);
    expect(find.text('No hearts left today'), findsOneWidget);
  });

  testWidgets(
    'reduced motion: the screen still works and nothing keeps animating',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h, reduceMotion: true));
      await tester.pumpAndSettle(); // would time out if the waveform ticker ran
      expect(find.text('Song 1'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Song 2'), findsOneWidget);
    },
  );

  testWidgets(
    'loading, error with retry, and the end of the feed all have words',
    (tester) async {
      phone(tester);
      final h = FeedHarness([
        [previewItem(1)],
      ]);
      h.api.failFeed = const OnlineFetchException(
        'The server is busy — still working on it.',
        statusCode: 504,
        busy: true,
      );
      await tester.pumpWidget(app(h));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The feed didn’t load'), findsOneWidget);
      expect(find.textContaining('busy'), findsOneWidget);
      h.api.failFeed = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Song 1'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
      await settle(tester);
      expect(find.text('You’ve heard what’s new'), findsOneWidget);
    },
  );

  testWidgets(
    'closing the screen stops the clip and gives the listener’s music back',
    (tester) async {
      phone(tester);
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(h.audio.calls.last, 'stop');
      expect(h.mainCalls, ['pause', 'resume']);
    },
  );

  testWidgets(
    'TV: a Next button and the arrow keys move on; a finished clip moves on by itself',
    (tester) async {
      phone(tester);
      PlatformUtils.debugTvOverride = true;
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      await tester.tap(find.byTooltip('Next song'));
      await settle(tester);
      expect(find.text('Song 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(find.text('Song 3'), findsOneWidget);
      h.audio.pos.add(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Song 4'), findsOneWidget);
    },
  );

  testWidgets(
    'Windows: a keyboard list; Down plays the next, H hearts, Space pauses',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PlatformUtils.debugDesktopOverride = true;
      final h = harness();
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(find.text('Song 1'), findsOneWidget);
      expect(
        find.text('Song 5'),
        findsOneWidget,
      ); // a list: everything is there
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(h.audio.calls.last, 'play https://cdn.example/p2.mp3');
      expect(h.api.signals, ['no pv_1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await settle(tester);
      expect(h.api.signals, ['no pv_1', 'yes pv_2']);
      expect(h.fetched, ['pv_2']);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(h.audio.calls.last, 'pause');
      expect(find.textContaining('hearts left today'), findsOneWidget);
    },
  );
}
