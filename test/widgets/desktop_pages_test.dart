import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/logic/social_providers.dart' show invitationCountProvider;
import 'package:navivibe/features/updates/logic/update_providers.dart' show updateCheckProvider;
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/artists_page.dart';
import 'package:navivibe/screens/library_screen.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/ui/media.dart';

List<(String, String)> savedAccounts = [];

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  @override
  Future<void> saveSettings(String url, String user, String pass) async => savedAccounts.add((user, pass));
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'yogesh', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
      : super(const PlayerState(
          queue: [],
          currentIndex: -1,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
          history: [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

Playlist _pl(String n, int songs) => Playlist(id: n, name: n, comment: '', songCount: songs, duration: 3000);
Album _al(String id, String name, String artist, int songs) =>
    Album(id: id, name: name, artist: artist, coverArt: id, songCount: songs, duration: 2400, year: 2024);

List<Override> _overrides() => [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      playerProvider.overrideWith((ref) => _FakePlayer()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      updateCheckProvider.overrideWith((ref) async => null),
      invitationCountProvider.overrideWithValue(0),
      sortedPlaylistsProvider.overrideWithValue(AsyncData([_pl('Late Night Drive', 14), _pl('Gym', 30), _pl('Focus', 7)])),
      sortedAlbumsProvider.overrideWithValue(AsyncData([_al('a1', 'Starboy', 'The Weeknd', 18), _al('a2', 'Alpha', 'Zed', 9)])),
      libraryArtistsProvider.overrideWith((ref) async => [const Artist(id: 'r1', name: 'Alan Walker', albumCount: 2)]),
    ];

Widget _app(Widget home) => PointerAnchor(
      child: ProviderScope(
        overrides: _overrides(),
        child: MaterialApp(
          theme: AppTheme.build(AppThemeTokens.fallback),
          builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
          home: home,
        ),
      ),
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_pages4');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    DesktopLayout.setLibraryGrid(true);
  });
  tearDown(() => PointerAnchor.reset());

  Future<void> size(WidgetTester tester, double w, double h) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(w, h);
    addTearDown(tester.view.reset);
  }

  group('Library on desktop', () {
    testWidgets('is the collection itself: tiles by default, Playlists first', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      for (final n in ['Late Night Drive', 'Gym', 'Focus']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.byType(MediaCard), findsNWidgets(3));
      expect(find.text('Starboy'), findsNothing);
    });

    testWidgets('the chips switch between Playlists, Albums and Artists', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Albums'));
      await tester.pump();
      expect(find.text('Starboy'), findsOneWidget);
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Alan Walker'), findsOneWidget);
    });

    testWidgets('the list toggle swaps tiles for rows with a sortable header, and is remembered', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('List'));
      await tester.pump();
      expect(find.byType(MediaCard), findsNothing);
      expect(DesktopLayout.libraryGrid.value, isFalse);
      expect(HiveBoxes.prefs.get('desktop_library_grid'), isFalse);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      // The cover starts at the page's left edge (24, where the title is), the name 52 after it.
      expect(tester.getTopLeft(find.text('Name')).dx, 24 + 40 + 12);

      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Late Night Drive'), lessThan(y('Focus')), reason: 'library order');
      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(y('Focus'), lessThan(y('Gym')), reason: 'name A–Z');
      expect(y('Gym'), lessThan(y('Late Night Drive')));
      await tester.tap(find.text('Name'));
      await tester.pump();
      expect(y('Late Night Drive'), lessThan(y('Focus')), reason: 'name Z–A');
      await tester.tap(find.text('Songs'));
      await tester.pump();
      expect(y('Focus'), lessThan(y('Late Night Drive')), reason: 'fewest songs first');
    });

    testWidgets('the sort menu sorts albums by artist', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Albums'));
      await tester.pump();
      await tester.tap(find.text('Library order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artist'));
      await tester.pumpAndSettle();
      expect(find.text('Artist A–Z'), findsOneWidget);
      double x(String t) => tester.getTopLeft(find.text(t)).dx; // tiles sit side by side
      expect(x('Starboy'), lessThan(x('Alpha')), reason: 'The Weeknd sorts before Zed');
    });

    testWidgets('right-click on a tile opens the menu at the cursor', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(tester.getCenter(find.text('Gym')) - const Offset(0, 60), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Shuffle'), findsWidgets);
    });

    testWidgets('a tile shows a Play button only while the pointer is on it', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      double opacity() => tester.widget<AnimatedOpacity>(find.descendant(of: find.byType(CardPlayButton), matching: find.byType(AnimatedOpacity)).first).opacity;
      expect(opacity(), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(MediaCard).first));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), 1);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), 0);
    });

    testWidgets('fits a narrow desktop window', (tester) async {
      await size(tester, 700, 600);
      await tester.pumpWidget(_app(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('List'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Settings on desktop', () {
    testWidgets('categories on the left, the chosen one on the right', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      for (final c in ['Account', 'Mascot', 'Playback', 'Audio quality', 'Downloads & storage', 'Smart Shuffle', 'Your data', 'About']) {
        expect(find.text(c), findsWidgets, reason: c);
      }
      // Account's rows are showing, Playback's are not.
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Living Artwork'), findsNothing);

      await tester.tap(find.text('Playback').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Living Artwork'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
    });

    testWidgets('the account saves itself a moment after you stop typing, and Undo puts it back', (tester) async {
      savedAccounts = [];
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save'), findsNothing, reason: 'no Save button on desktop');
      await tester.enterText(find.widgetWithText(CupertinoTextField, 'yogesh'), 'yogesh2');
      await tester.pump(const Duration(milliseconds: 300));
      expect(savedAccounts, isEmpty, reason: 'not while still typing');
      await tester.pump(const Duration(milliseconds: 800));
      expect(savedAccounts.single.$1, 'yogesh2');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Account saved'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(savedAccounts.last.$1, 'yogesh');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('rows are flat: a section whose header repeats the category leaves it out', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Playback').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Playback'), findsNWidgets(2), reason: 'the nav row and the page title, not a third time');
    });

    testWidgets('a phone keeps one long list', (tester) async {
      PlatformUtils.debugDesktopOverride = false;
      await size(tester, 393, 852);
      await tester.pumpWidget(_app(const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Username'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('shelves', () {
    Widget shelf({required List<String> log, int count = 14}) => _app(Scaffold(
          body: MediaShelf(
            title: 'Recently Played',
            cardSize: 170,
            itemCount: count,
            itemBuilder: (context, i) => MediaCard(
              title: 'Album $i',
              subtitle: 'Artist',
              size: 170,
              onTap: () => log.add('open $i'),
              onPlay: () => log.add('play $i'),
            ),
          ),
        ));

    testWidgets('arrow buttons appear while the pointer is on the shelf, and page it', (tester) async {
      await size(tester, 1000, 500);
      await tester.pumpWidget(shelf(log: []));
      await tester.pump();
      expect(find.byTooltip('Scroll right'), findsNothing, reason: 'hidden until hovered');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(500, 150));
      await tester.pump();
      expect(find.byTooltip('Scroll right'), findsOneWidget);
      expect(find.byTooltip('Scroll left'), findsNothing, reason: 'already at the start');
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.pixels, 0);
      await tester.tap(find.byTooltip('Scroll right'));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(300));
      expect(find.byTooltip('Scroll left'), findsOneWidget);
      await tester.tap(find.byTooltip('Scroll left'));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 0);
      await mouse.moveTo(const Offset(5, 450));
      await tester.pump();
      expect(find.byTooltip('Scroll right'), findsNothing);
    });

    testWidgets('a short shelf has no arrows to show', (tester) async {
      await size(tester, 1000, 500);
      await tester.pumpWidget(shelf(log: [], count: 3));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(300, 150));
      await tester.pump();
      expect(find.byTooltip('Scroll right'), findsNothing);
    });

    testWidgets('a card shows Play on hover; Play plays without opening, the card opens', (tester) async {
      final log = <String>[];
      await size(tester, 1000, 500);
      await tester.pumpWidget(shelf(log: log));
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      double opacity(int i) => tester
          .widget<AnimatedOpacity>(find.descendant(of: find.byType(CardPlayButton).at(i), matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(0), 0);
      await mouse.moveTo(const Offset(100, 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(0), 1);
      expect(opacity(1), 0, reason: 'only the card under the pointer');
      await tester.tap(find.byTooltip('Play Album 0'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['play 0']);
      await tester.tap(find.text('Album 0'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['play 0', 'open 0']);
    });

    testWidgets('a phone card has no Play overlay at all', (tester) async {
      PlatformUtils.debugDesktopOverride = false;
      await size(tester, 400, 600);
      await tester.pumpWidget(shelf(log: []));
      expect(find.byType(CardPlayButton), findsNothing);
    });
  });

  group('compact header actions', () {
    testWidgets('Play is a round button on desktop, with Shuffle beside it', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(_app(Scaffold(
        body: Center(child: PlayShuffleButtons(onPlay: () {}, onShuffle: () {})),
      )));
      expect(find.text('Play'), findsNothing, reason: 'no 148-wide capsule');
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.bySemanticsLabel('Shuffle'), findsOneWidget);
    });

    testWidgets('a phone keeps the capsule', (tester) async {
      PlatformUtils.debugDesktopOverride = false;
      await size(tester, 393, 852);
      await tester.pumpWidget(_app(Scaffold(
        body: Center(child: PlayShuffleButtons(onPlay: () {}, onShuffle: () {})),
      )));
      expect(find.text('Play'), findsOneWidget);
    });
  });
}
