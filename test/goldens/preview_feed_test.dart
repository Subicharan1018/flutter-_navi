/// Swipe to fetch: the phone's full-screen pager (cover, waveform, heart ring, title) and the Windows keyboard list.
///
///   flutter test test/goldens/preview_feed_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/preview_feed/data/preview_models.dart';
import 'package:navivibe/features/preview_feed/ui/art_tint.dart';
import 'package:navivibe/features/preview_feed/ui/preview_feed_screen.dart';
import 'package:navivibe/player/artwork.dart' show debugCoverImageOverride;
import 'package:navivibe/utils/platform_utils.dart';

import '../features/preview_feed/preview_feed_fakes.dart';
import 'fake_covers.dart';
import 'golden_fonts.dart';

const _items = [
  ('Vaa Vaathiyaar', 'Anirudh Ravichander', 'Trending · tamil #1', 'chart'),
  ('Kadhal Oru Aagayam', 'Sid Sriram', 'New release', 'release'),
  ('Neela Nira Sooriyan', 'Sam C S', 'A friend hearted this', 'friend'),
  ('Oru Naalil', 'Yuvan Shankar Raja', 'Trending · tamil #4', 'chart'),
  ('Mayakkam Enna', 'G. V. Prakash', 'Trending · tamil #5', 'chart'),
];

FeedHarness _harness() => FeedHarness([
  [
    for (var i = 0; i < _items.length; i++)
      PreviewItem(
        key: 'pv_$i',
        title: _items[i].$1,
        artist: _items[i].$2,
        artUrl: 'c$i',
        previewUrl: 'https://cdn.example/p$i.mp3',
        source: PreviewSource.parse(_items[i].$4),
        reason: _items[i].$3,
      ),
  ],
])..api.remaining = 17;

Widget _app(FeedHarness h) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: h.overrides.cast<Override>(),
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: const PreviewFeedScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    debugCoverImageOverride = null;
    debugTintSampler = null;
  });

  Future<void> play(
    WidgetTester tester,
    FeedHarness h, {
    double seconds = 12,
  }) async {
    final sw = await tester.runAsync(() => texturedCovers());
    debugCoverImageOverride = (url, key) => sw![url] ?? sw['c0']!;
    // A fixed tone per cover: no network, no image cache.
    debugTintSampler = (url) async => const [
      Color(0xFF3A2218),
      Color(0xFF1B2A3A),
      Color(0xFF2D2236),
      Color(0xFF30281A),
      Color(0xFF1D2E2A),
    ][int.parse(url.substring(1)) % 5];
    await tester.pumpWidget(_app(h));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    ); // the covers decode off the test clock
    await tester.pump();
    h.audio.pos.add(Duration(milliseconds: (seconds * 1000).round()));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PlatformUtils.debugDesktopOverride = false;
    await play(tester, _harness());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_feed/preview_feed_phone.png'),
    );
  });

  testWidgets('phone, hearted', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    PlatformUtils.debugDesktopOverride = false;
    final h = _harness();
    await play(tester, h, seconds: 21);
    await tester.tap(find.bySemanticsLabel('Heart to fetch this song'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_feed/preview_feed_phone_hearted.png'),
    );
  });

  testWidgets('windows', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PlatformUtils.debugDesktopOverride = true;
    await play(tester, _harness());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_feed/preview_feed_windows.png'),
    );
  });
}
