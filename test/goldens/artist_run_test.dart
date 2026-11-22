/// The artist page's "With You" block and album timeline ("The Run"), phone
/// 390×844 @3x and Windows 1280×800.
///
///   flutter test test/goldens/artist_run_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/artist_run/logic/artist_run.dart';
import 'package:navivibe/features/artist_run/ui/artist_run.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/utils/platform_utils.dart';

import 'golden_fonts.dart';

Album _a(int i, String name, int year, int songs) =>
    Album(id: 'al$i', name: name, artist: 'A. R. Rahman', coverArt: 'al$i', songCount: songs, duration: 0, year: year);

final _albums = [
  _a(1, 'Ponniyin Selvan', 2022, 6),
  _a(2, 'Mersal', 2017, 6),
  _a(3, 'Kaatru Veliyidai', 2017, 8),
  _a(4, 'OK Kanmani', 2015, 9),
  _a(5, 'Enthiran', 2010, 8),
  _a(6, 'Vinnaithaandi Varuvaayaa', 2010, 9),
  _a(7, 'Sivaji', 2007, 6),
  _a(8, 'Kannathil Muthamittal', 2002, 8),
  _a(9, 'Bombay', 1995, 8),
  _a(10, 'Roja', 1992, 6),
  _a(11, 'Demo Tapes', 0, 4),
];

ArtistHistory _history() => ArtistHistory.from([
  for (var i = 0; i < 40; i++)
    ArtistPlay(song: 'Kannalane', album: 'Bombay', at: DateTime(2022, 3, 5 + i % 20), seconds: 330),
  for (var i = 0; i < 18; i++)
    ArtistPlay(song: 'Chinna Chinna Aasai', album: 'Roja', at: DateTime(2024, 1, 2 + i), seconds: 280),
  for (var i = 0; i < 9; i++)
    ArtistPlay(song: 'Mersal Arasan', album: 'Mersal', at: DateTime(2025, 9, 1 + i), seconds: 240),
  ArtistPlay(song: 'Ponni Nadhi', album: 'Ponniyin Selvan', at: DateTime(2026, 11, 20), seconds: 200),
]);

Widget _page(BuildContext context, {ValueChanged<ReleaseYear>? onYear, ValueChanged<Album>? onOpen}) {
  final history = _history();
  return CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: ArtistWithYou(history: history)),
      ...releaseTimelineSlivers(
        context,
        years: groupByYear(_albums),
        history: history,
        coverUrl: (_) => '',
        onOpen: onOpen ?? (_) {},
        onPlayYear: onYear ?? (_) {},
        onLongPress: (_) {},
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ],
  );
}

Widget _app({ValueChanged<ReleaseYear>? onYear, ValueChanged<Album>? onOpen}) {
  final tokens = AppThemeTokens.fallback;
  return ThemeTokens(
    tokens: tokens,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(tokens),
      home: Builder(
        builder: (c) => Scaffold(
          backgroundColor: tokens.bgBase,
          body: _page(c, onYear: onYear, onOpen: onOpen),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  testWidgets('phone', (tester) async {
    view(tester, const Size(390, 844), 3);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('artist_run/run_phone.png'));
  });

  testWidgets('windows', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    view(tester, const Size(1280, 800), 1);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('artist_run/run_windows.png'));
  });

  testWidgets('tapping a year plays that year; tapping a cover opens the album', (tester) async {
    view(tester, const Size(390, 844), 3);
    ReleaseYear? played;
    Album? opened;
    await tester.pumpWidget(_app(onYear: (y) => played = y, onOpen: (a) => opened = a));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2017'));
    expect(played?.year, 2017);
    expect(played?.albums.length, 2);
    await tester.tap(find.text('Mersal').last);
    expect(opened?.name, 'Mersal');
  });

  testWidgets('nothing animates while the page sits', (tester) async {
    view(tester, const Size(390, 844), 3);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('an artist never played shows no With You block', (tester) async {
    view(tester, const Size(390, 400), 3);
    await tester.pumpWidget(
      ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: const MaterialApp(
          home: Scaffold(body: ArtistWithYou(history: ArtistHistory())),
        ),
      ),
    );
    expect(find.text('With You'), findsNothing);
  });
}
