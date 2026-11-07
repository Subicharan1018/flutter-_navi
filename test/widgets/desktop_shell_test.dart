import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/models/artist.dart';
import 'package:navivibe/features/social/logic/social_providers.dart' show invitationCountProvider;
import 'package:navivibe/features/updates/logic/update_providers.dart' show updateCheckProvider;
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/search_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library/artists_page.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/library_rail.dart';
import 'package:navivibe/widgets/shell/desktop/resize_handle.dart';
import 'package:navivibe/widgets/shell/desktop/top_bar.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'yogesh', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

Playlist _pl(String id, String name) => Playlist(id: id, name: name, comment: '', songCount: 12, duration: 3000);
Album _al(String id, String name, String artist) =>
    Album(id: id, name: name, artist: artist, coverArt: id, songCount: 10, duration: 2400, year: 2024);

List<Override> _overrides() => [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      playerProvider.overrideWith((ref) => _FakePlayer()),
      updateCheckProvider.overrideWith((ref) async => null),
      invitationCountProvider.overrideWithValue(0),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      sortedPlaylistsProvider.overrideWithValue(AsyncData([_pl('1', 'Late Night Drive'), _pl('2', 'Gym'), _pl('3', 'Focus')])),
      sortedAlbumsProvider.overrideWithValue(AsyncData([_al('a1', 'Short n’ Sweet', 'Sabrina Carpenter'), _al('a2', 'Starboy', 'The Weeknd')])),
      libraryArtistsProvider.overrideWith((ref) async => [Artist(id: 'r1', name: 'Alan Walker', albumCount: 2)]),
    ];

Widget _app(Widget child, {List<Override>? overrides}) => PointerAnchor(
      child: ProviderScope(
        overrides: overrides ?? _overrides(),
        child: MaterialApp(
          theme: AppTheme.build(AppThemeTokens.fallback),
          builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_shell');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    DesktopLayout.debugReset();
  });
  tearDown(() async {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
    activeTab.value = AppTab.home;
  });

  group('back and forward', () {
    Future<GlobalKey<NavigatorState>> host(WidgetTester tester) async {
      final key = tabNavigators[AppTab.home]!;
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          key: key,
          observers: [tabTrails[AppTab.home]!],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (c) => Builder(builder: (ctx) {
                lastContext = ctx;
                return const Text('root');
              })),
        ),
      ));
      activeTab.value = AppTab.home;
      await tester.pump();
      return key;
    }

    testWidgets('Back remembers the page, Forward brings it back, a new page ends Forward', (tester) async {
      await host(tester);
      expect(canGoForward(), isFalse);
      navigateInApp(lastContext, const Text('albums'), title: 'Albums');
      await tester.pumpAndSettle();
      navigateInApp(lastContext, const Text('abbey'), title: 'Abbey Road');
      await tester.pumpAndSettle();
      expect(find.text('abbey'), findsOneWidget);

      expect(popActiveTab(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('albums'), findsOneWidget);
      expect(canGoForward(), isTrue);

      expect(goForward(lastContext), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('abbey'), findsOneWidget);
      expect(canGoForward(), isFalse);

      // Back twice, then somewhere new: forward is gone.
      popActiveTab();
      await tester.pumpAndSettle();
      popActiveTab();
      await tester.pumpAndSettle();
      expect(canGoForward(), isTrue);
      navigateInApp(lastContext, const Text('elsewhere'), title: 'Elsewhere');
      await tester.pumpAndSettle();
      expect(canGoForward(), isFalse);
      expect(goForward(lastContext), isFalse);
    });
  });

  group('top bar', () {
    testWidgets('typing in the search field sets the query and opens Search; Esc clears', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);
      addTearDown(tester.view.reset);
      late ProviderContainer container;
      await tester.pumpWidget(_app(Consumer(builder: (c, ref, _) {
        container = ProviderScope.containerOf(c);
        return const DesktopTopBar();
      })));
      await tester.pump();
      tabRequestSeen = null;
      tabRequest.addListener(() => tabRequestSeen = tabRequest.value);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tabRequestSeen, AppTab.search, reason: 'focusing the field opens Search');
      await tester.enterText(find.byType(TextField), 'starboy');
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(searchQueryProvider), 'starboy');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(searchQueryProvider), '');
    });

    testWidgets('the search field takes the focus when asked (Ctrl+K)', (tester) async {
      await tester.pumpWidget(_app(const DesktopTopBar()));
      expect(desktopSearchFocus.hasFocus, isFalse);
      desktopSearchFocus.requestFocus();
      await tester.pump();
      expect(desktopSearchFocus.hasFocus, isTrue);
      desktopSearchFocus.unfocus();
    });

    testWidgets('Back and Forward are disabled with nowhere to go', (tester) async {
      await tester.pumpWidget(_app(const DesktopTopBar()));
      await tester.pump();
      final back = find.bySemanticsLabel('Back (Alt+←)');
      expect(back, findsOneWidget);
    });

    testWidgets('the profile shows the first letter of the account', (tester) async {
      await tester.pumpWidget(_app(const DesktopTopBar()));
      expect(find.text('Y'), findsOneWidget);
    });

    testWidgets('the bar fits from 600 to 1920 wide', (tester) async {
      for (final w in [600.0, 900.0, 1366.0, 1920.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 700);
        await tester.pumpWidget(_app(const DesktopTopBar()));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
      addTearDown(tester.view.reset);
    });
  });

  group('library rail', () {
    Future<void> rail(WidgetTester tester, {double w = 1366, bool forceCollapsed = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Row(children: [
        LibraryRail(tab: AppTab.home, onSelect: (_) {}, forceCollapsed: forceCollapsed),
        const Expanded(child: SizedBox()),
      ])));
      await tester.pump();
    }

    testWidgets('lists compact destinations, then the library with playlists first', (tester) async {
      await rail(tester);
      for (final l in ['Home', 'Shuffle', 'Jam', 'Stats', 'Your Library', 'Settings']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('Late Night Drive'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Starboy'), findsNothing, reason: 'albums are behind their filter');
    });

    testWidgets('no destination is listed twice (Library, Playlists, Albums, Songs rows are gone)', (tester) async {
      await rail(tester);
      expect(find.text('Playlists'), findsOneWidget, reason: 'only the filter chip');
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('the Albums chip swaps the list, tapping it again shows everything', (tester) async {
      await rail(tester);
      await tester.tap(find.text('Albums'));
      await tester.pump();
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Late Night Drive'), findsNothing);
      await tester.tap(find.text('Albums'));
      await tester.pump();
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Late Night Drive'), findsOneWidget);
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(find.text('Alan Walker'), findsOneWidget);
    });

    testWidgets('find narrows the list; sort A–Z reorders it', (tester) async {
      await rail(tester);
      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pump();
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Focus'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Late Night Drive'), lessThan(y('Focus')), reason: 'library order');
      await tester.tap(find.byTooltip('Sort: library order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alphabetical'));
      await tester.pumpAndSettle();
      expect(y('Focus'), lessThan(y('Late Night Drive')), reason: 'A–Z');
    });

    testWidgets('collapse goes to icons only, and the choice is remembered', (tester) async {
      await rail(tester);
      await tester.tap(find.byTooltip('Collapse the library'));
      await tester.pump();
      expect(DesktopLayout.railCollapsed.value, isTrue);
      expect(find.text('Your Library'), findsNothing);
      expect(tester.getSize(find.byType(LibraryRail)).width, DesktopLayout.railIcons);
      expect(HiveBoxes.prefs.get('desktop_rail_collapsed'), isTrue);
      await tester.tap(find.byTooltip('Expand the library'));
      await tester.pump();
      expect(find.text('Your Library'), findsOneWidget);
    });

    testWidgets('a narrow window is icons whatever was chosen', (tester) async {
      await rail(tester, w: 700, forceCollapsed: true);
      expect(find.text('Your Library'), findsNothing);
      expect(tester.getSize(find.byType(LibraryRail)).width, DesktopLayout.railIcons);
      expect(tester.takeException(), isNull);
    });

    testWidgets('right-click on a playlist opens its menu', (tester) async {
      await rail(tester);
      await tester.tapAt(tester.getCenter(find.text('Gym')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Shuffle'), findsWidgets);
    });
  });

  group('resizing', () {
    testWidgets('dragging the handle moves the width, clamps it, and saves it when released', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 200,
              child: ResizeHandle(
                label: 'x',
                growsRight: true,
                onDrag: (d) => DesktopLayout.dragRail(DesktopLayout.railWidth.value + d),
                onEnd: DesktopLayout.saveRail,
                onReset: DesktopLayout.resetRail,
              ),
            ),
          ),
        ),
      ));
      expect(DesktopLayout.railWidth.value, DesktopLayout.railDefault);
      final g = await tester.startGesture(tester.getCenter(find.byType(ResizeHandle)), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(30, 0));
      }

      await tester.pump();
      expect(DesktopLayout.railWidth.value, greaterThan(DesktopLayout.railDefault + 60));
      await g.moveBy(const Offset(900, 0));
      await tester.pump();
      expect(DesktopLayout.railWidth.value, DesktopLayout.railMax, reason: 'clamped');
      await g.up();
      await tester.pump();
      expect(HiveBoxes.prefs.get('desktop_rail_width'), DesktopLayout.railMax);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('double-click puts the width back; arrow keys nudge it', (tester) async {
      DesktopLayout.dragRail(380);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 200,
              child: ResizeHandle(
                label: 'x',
                growsRight: true,
                onDrag: (d) => DesktopLayout.dragRail(DesktopLayout.railWidth.value + d),
                onEnd: DesktopLayout.saveRail,
                onReset: DesktopLayout.resetRail,
              ),
            ),
          ),
        ),
      ));
      final c = tester.getCenter(find.byType(ResizeHandle));
      await tester.tapAt(c);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(c);
      await tester.pump(const Duration(milliseconds: 400));
      expect(DesktopLayout.railWidth.value, DesktopLayout.railDefault);

      Focus.of(tester.element(find.descendant(of: find.byType(ResizeHandle), matching: find.byType(GestureDetector)).first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(DesktopLayout.railWidth.value, DesktopLayout.railDefault + 16);
    });

    test('the right panel is clamped to its own range', () {
      DesktopLayout.dragPanel(9999);
      expect(DesktopLayout.panelWidth.value, DesktopLayout.panelMax);
      DesktopLayout.dragPanel(1);
      expect(DesktopLayout.panelWidth.value, DesktopLayout.panelMin);
    });
  });
}

late BuildContext lastContext;
AppTab? tabRequestSeen;

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
