import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/keyboard_shortcuts.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/desktop_layout.dart';
import 'package:navivibe/widgets/shell/desktop/focus_regions.dart';
import 'package:navivibe/widgets/shell/desktop/now_playing_panel.dart';
import 'package:navivibe/widgets/art/navi_icons.dart' show NaviIcon;
import 'package:navivibe/widgets/table/song_table.dart';

Song _s(int i) => Song(
      id: 's$i',
      title: 'Song ${String.fromCharCode(64 + i)}',
      artist: 'Artist $i',
      album: 'Album $i',
      coverArt: 's$i',
      duration: 100 + i * 10,
      track: i,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
    );

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

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

Widget _app(Widget home) {
  final List<Override> overrides = [
    playerProvider.overrideWith((ref) => _FakePlayer()),
    settingsProvider.overrideWith((ref) => _FakeSettings()),
    subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    catalogSongProvider.overrideWith((ref, id) => null),
  ];
  return PointerAnchor(
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: Scaffold(body: home),
      ),
    ),
  );
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_focus');
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
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    PointerAnchor.reset();
  });

  Future<void> size(WidgetTester tester, double w, double h) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(w, h);
    addTearDown(tester.view.reset);
  }

  FocusNode focusOf(WidgetTester tester, Finder inside) =>
      Focus.of(tester.element(find.descendant(of: inside, matching: find.byType(GestureDetector)).first));

  group('sortable column headers', () {
    Widget table() => _app(CustomScrollView(slivers: [
          SongTableSliver(songs: [for (final i in [3, 1, 2]) _s(i)], onPlay: (a, b) {}),
        ]));

    Finder header(String label) => find.ancestor(of: find.text(label), matching: find.byType(NaviPressable));

    List<String> order(WidgetTester tester) {
      final ys = {for (final t in ['Song A', 'Song B', 'Song C']) t: tester.getTopLeft(find.text(t)).dy};
      return (ys.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).map((e) => e.key).toList();
    }

    testWidgets('are labelled controls, not bare text', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      final handle = tester.ensureSemantics();
      for (final l in ['Title', 'Album', 'Time']) {
        expect(find.bySemanticsLabel(RegExp('Sort by $l')), findsOneWidget, reason: l);
      }
      handle.dispose();
    });

    testWidgets('can be reached by keyboard: Enter sorts, Enter again reverses, a third restores', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      expect(order(tester).first, 'Song C');
      focusOf(tester, header('Title')).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(order(tester).first, 'Song A');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(order(tester).first, 'Song C');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(order(tester).first, 'Song C', reason: 'back to the list order');
    });

    testWidgets('Space sorts too', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      focusOf(tester, header('Time')).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(order(tester).first, 'Song A');
    });

    testWidgets('the focused header shows the white ring', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      focusOf(tester, header('Album')).requestFocus();
      await tester.pump();
      final ring = find.descendant(
        of: header('Album'),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null),
      );
      expect(ring, findsOneWidget);
      final border = ((tester.widget<DecoratedBox>(ring).decoration) as BoxDecoration).border as Border;
      expect(border.top.width, 2);
      expect(border.top.color, AppThemeTokens.fallback.accent);
    });

    testWidgets('the sorted column shows its direction, the others do not', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(find.descendant(of: header('Title'), matching: find.byType(NaviIcon)), findsOneWidget, reason: 'the direction arrow');
      expect(find.descendant(of: header('Album'), matching: find.byType(NaviIcon)), findsNothing);
    });
  });

  group('row states', () {
    Color? fillOf(WidgetTester tester, String title) {
      final c = tester.widget<Container>(find.ancestor(of: find.text(title), matching: find.byType(Container)).first);
      return ((c.decoration) as BoxDecoration?)?.color;
    }

    BoxDecoration? outlineOf(WidgetTester tester, String title) {
      for (final e in find.ancestor(of: find.text(title), matching: find.byType(Container)).evaluate()) {
        final c = e.widget as Container;
        if (c.foregroundDecoration != null) return c.foregroundDecoration as BoxDecoration;
      }
      return null;
    }

    Widget table() => _app(CustomScrollView(slivers: [
          SongTableSliver(songs: [for (final i in [1, 2, 3]) _s(i)], onPlay: (a, b) {}),
        ]));

    testWidgets('hover, selected and keyboard focus each look different', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      // Hover Song A: a 9% wash, no outline.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Song A')));
      await tester.pump();
      final hover = fillOf(tester, 'Song A')!;
      expect(hover.a, closeTo(0.09, 0.01));
      expect(outlineOf(tester, 'Song A'), isNull);
      // Select Song B: a stronger fill.
      await tester.tap(find.text('Song B'));
      await tester.pump(const Duration(milliseconds: 350));
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      final selected = fillOf(tester, 'Song B')!;
      expect(selected.a, greaterThan(hover.a + 0.05));
      // Move the cursor with the keyboard to Song C: an outline, not a fill.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final outline = outlineOf(tester, 'Song C');
      expect(outline, isNotNull);
      expect((outline!.border as Border).top.width, 2);
      expect((outline.border as Border).top.color, AppThemeTokens.fallback.accent);
      expect(outlineOf(tester, 'Song A'), isNull);
    });

    testWidgets('the row Play button and the row text meet the size floor', (tester) async {
      await size(tester, 1366, 768);
      await tester.pumpWidget(table());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Song A')));
      await tester.pump();
      expect(tester.getSize(find.byTooltip('Play').first).height, greaterThanOrEqualTo(32));
      final artist = tester.widget<Text>(find.text('Artist 1'));
      expect(artist.style!.fontSize, greaterThanOrEqualTo(12));
    });
  });

  group('F6', () {
    Widget regions() => _app(
          NaviKeyboardShortcuts(
            commands: ShellCommands(
              openSearch: () {},
              focusSearch: () {},
              openSettings: () {},
              selectTab: (_) {},
              goBack: () => false,
            ),
            child: Row(children: [
              FocusRegion(order: 1, name: 'Library', child: ElevatedButton(onPressed: () {}, child: const Text('rail'))),
              FocusRegion(order: 2, name: 'Page', child: ElevatedButton(onPressed: () {}, child: const Text('page'))),
              FocusRegion(order: 3, name: 'Now Playing', child: ElevatedButton(onPressed: () {}, child: const Text('panel'))),
              FocusRegion(order: 4, name: 'Player', child: ElevatedButton(onPressed: () {}, child: const Text('bar'))),
            ]),
          ),
        );

    String? focused(WidgetTester tester) {
      for (final t in ['rail', 'page', 'panel', 'bar']) {
        final n = Focus.of(tester.element(find.text(t)));
        if (n.hasFocus) return t;
      }
      return null;
    }

    testWidgets('F6 moves to the next part of the window, wrapping round; Shift+F6 goes back', (tester) async {
      await size(tester, 1000, 400);
      await tester.pumpWidget(regions());
      await tester.pump();
      expect(FocusRegion.names, ['Library', 'Page', 'Now Playing', 'Player']);
      Focus.of(tester.element(find.text('rail'))).requestFocus(); // keys need somewhere to land
      await tester.pump();
      expect(focused(tester), 'rail');
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(focused(tester), 'page');
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(focused(tester), 'bar');
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(focused(tester), 'rail', reason: 'wraps');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focused(tester), 'bar', reason: 'Shift+F6 goes back');
    });

    testWidgets('a part of the window that is not on screen is skipped', (tester) async {
      await size(tester, 1000, 400);
      await tester.pumpWidget(_app(
        NaviKeyboardShortcuts(
          commands: ShellCommands(openSearch: () {}, focusSearch: () {}, openSettings: () {}, selectTab: (_) {}, goBack: () => false),
          child: Row(children: [
            FocusRegion(order: 1, name: 'Library', child: ElevatedButton(onPressed: () {}, child: const Text('rail'))),
            FocusRegion(order: 4, name: 'Player', child: ElevatedButton(onPressed: () {}, child: const Text('bar'))),
          ]),
        ),
      ));
      Focus.of(tester.element(find.text('rail'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(Focus.of(tester.element(find.text('bar'))).hasFocus, isTrue);
    });
  });

  group('panel overlay returns focus', () {
    testWidgets('closing the panel puts focus back on the control that opened it', (tester) async {
      await size(tester, 1100, 700);
      final open = ValueNotifier<PanelKind?>(null);
      await tester.pumpWidget(_app(
        ValueListenableBuilder<PanelKind?>(
          valueListenable: open,
          builder: (context, panel, _) => PanelOverlay(
            panel: panel,
            onChange: (p) => open.value = p,
            onClose: () => open.value = null,
            child: Center(
              child: NaviPressable(onTap: () => open.value = PanelKind.lyrics, child: const SizedBox(width: 80, height: 40, child: Text('Lyrics'))),
            ),
          ),
        ),
      ));
      final button = focusOf(tester, find.byType(NaviPressable));
      await tester.tap(find.text('Lyrics'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(open.value, PanelKind.lyrics);
      expect(button.hasFocus, isFalse, reason: 'focus moved into the panel');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(open.value, isNull);
      expect(button.hasPrimaryFocus, isTrue, reason: 'focus is back on the button');
    });
  });
}
