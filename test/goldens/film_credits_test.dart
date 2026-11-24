/// Film page and Credit page (phone 390 wide @2x, Windows 1280x900): the credit lines, owned songs, the soundtrack tracks
/// you do not have, and a music director grouped by film.
///
///   flutter test test/goldens/film_credits_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/film_credits/ui/credit_screen.dart';
import 'package:navivibe/features/film_credits/ui/film_screen.dart';
import 'package:navivibe/models/composer.dart';
import 'package:navivibe/player/artwork.dart' show debugCoverImageOverride;

import '../features/film_credits/harness.dart';
import 'fake_covers.dart';
import 'golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => debugCoverImageOverride = null);

  Future<void> load(WidgetTester tester, Widget home, Size logical, double dpr) async {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final sw = await tester.runAsync(() => texturedCovers());
    debugCoverImageOverride = (url, key) => sw![url] ?? sw['c0']!;
    await tester.pumpWidget(app(home));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
  }

  testWidgets('film page, phone', (tester) async {
    await load(tester, const FilmScreen(filmKey: 'remo', title: 'Remo'), const Size(390, 1250), 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('film_credits/film_phone.png'));
  });

  testWidgets('credit page, phone', (tester) async {
    await load(tester, CreditScreen(personKey: nameKey('Anirudh Ravichander'), name: 'Anirudh Ravichander'), const Size(390, 1000), 2);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('film_credits/credit_phone.png'));
  });

  testWidgets('film page, windows', (tester) async {
    await load(tester, const FilmScreen(filmKey: 'remo', title: 'Remo'), const Size(1280, 900), 1);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('film_credits/film_windows.png'));
  });
}
