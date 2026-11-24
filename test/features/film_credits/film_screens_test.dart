import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/film_credits/logic/credit_index.dart';
import 'package:navivibe/features/film_credits/ui/credit_screen.dart';
import 'package:navivibe/features/film_credits/ui/credits_browse.dart';
import 'package:navivibe/features/film_credits/ui/film_screen.dart';
import 'package:navivibe/models/composer.dart';

import 'harness.dart';

void main() {
  useFakeCovers();
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1600) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  testWidgets('film page: credits, owned songs, the soundtrack tracks you do not have', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const FilmScreen(filmKey: 'remo', title: 'Remo')));
    await settle(tester);
    expect(find.text('Remo'), findsWidgets);
    expect(find.textContaining('2016'), findsWidgets);
    expect(find.text('Directed by'), findsOneWidget);
    expect(find.text('Bakkiyaraj Kannan'), findsOneWidget);
    expect(find.text('Thamarai'), findsOneWidget);
    expect(find.text('Sirikkadhey'), findsOneWidget);
    expect(find.text('Not in Your Library'), findsOneWidget);
    expect(find.text('Unnaal Unnaal'), findsOneWidget);
    expect(find.text('Kadhal Cricket'), findsOneWidget);
    expect(find.textContaining('2 not in your library'), findsOneWidget);
    expect(find.text('Find the rest of this soundtrack'), findsOneWidget); // the hook into online fetch
  });

  testWidgets('film page with no server facts shows only what the library says', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const FilmScreen(filmKey: 'kodi', title: 'Kodi')));
    await settle(tester);
    expect(find.text('Ei Suzhali'), findsOneWidget);
    expect(find.text('Not in Your Library'), findsNothing); // no track list = nothing invented
    expect(find.text('Directed by'), findsNothing);
  });

  testWidgets('play on a film queues its songs in order', (tester) async {
    phone(tester);
    final player = FakePlayer();
    await tester.pumpWidget(app(const FilmScreen(filmKey: 'remo', title: 'Remo'), player: player));
    await settle(tester);
    await tester.tap(find.text('Play').first);
    await tester.pump();
    expect(player.queues, [
      ['1', '2']
    ]);
  });

  testWidgets('a name on the film page opens that person', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const FilmScreen(filmKey: 'remo', title: 'Remo')));
    await settle(tester);
    await tester.tap(find.text('Thamarai'));
    await settle(tester);
    expect(find.byType(CreditScreen), findsOneWidget);
  });

  testWidgets('credit page: roles filter, songs grouped by film', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(CreditScreen(personKey: nameKey('Anirudh Ravichander'), name: 'Anirudh Ravichander')));
    await settle(tester);
    expect(find.text('Music director · Singer'), findsOneWidget);
    expect(find.text('Remo'), findsOneWidget); // a film header
    expect(find.text('3'), findsOneWidget); // the other film, "3"
    expect(find.text('Other Songs'), findsNothing);
    await tester.ensureVisible(find.text('Singer 2'));
    await tester.tap(find.text('Singer 2'));
    await settle(tester);
    expect(find.text('Why This Kolaveri Di'), findsNothing); // he composed it, did not sing it: filtered out
    expect(find.text('Sirikkadhey'), findsOneWidget);
  });

  testWidgets('a person with one role shows no filter, a link with a role opens on it', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(CreditScreen(personKey: nameKey('Thamarai'), name: 'Thamarai', role: CreditRole.lyricist)));
    await settle(tester);
    expect(find.textContaining('All '), findsNothing);
    expect(find.text('Sirikkadhey'), findsOneWidget);
  });

  testWidgets('unknown person: an honest empty state', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(CreditScreen(personKey: nameKey('Nobody'), name: 'Nobody')));
    await settle(tester);
    expect(find.text('No songs credited here'), findsOneWidget);
  });

  testWidgets('browse lists: Films A-Z and people by role', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const FilmsPage()));
    await settle(tester);
    expect(find.text('Remo'), findsOneWidget);
    expect(find.text('Kodi'), findsOneWidget);
    await tester.pumpWidget(app(const PeoplePage(role: CreditRole.lyricist)));
    await settle(tester);
    expect(find.text('Thamarai'), findsOneWidget);
    expect(find.text('Vivek'), findsOneWidget);
    expect(find.text('Anirudh Ravichander'), findsNothing);
  });

  testWidgets('Search browse entry: rows with counts, each opens its list', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const Scaffold(body: CustomScrollView(slivers: [CreditsBrowseSection()]))));
    await settle(tester);
    expect(find.textContaining('Films  ·  3'), findsOneWidget);
    expect(find.textContaining('Music Directors'), findsOneWidget);
    expect(find.textContaining('Lyricists'), findsOneWidget);
    expect(find.textContaining('Singers'), findsOneWidget);
  });

  testWidgets('film search section matches by title, spelling-insensitive', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const Scaffold(body: CustomScrollView(slivers: [FilmSearchSection(query: 'REM')]))));
    await settle(tester);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Remo'), findsOneWidget);
    expect(find.text('Kodi'), findsNothing);
  });

  testWidgets('artist page section: the films an artist is credited on', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const Scaffold(body: CustomScrollView(slivers: [ArtistFilmsSection(artistName: 'Anirudh Ravichander')]))));
    await settle(tester);
    expect(find.text('In Films'), findsOneWidget);
    expect(find.text('Remo'), findsOneWidget);
    await tester.pumpWidget(app(const Scaffold(body: CustomScrollView(slivers: [ArtistFilmsSection(artistName: 'Nobody At All')]))));
    await settle(tester);
    expect(find.text('In Films'), findsNothing);
  });
}
