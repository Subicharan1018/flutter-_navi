// The mini player mounted the way main.dart mounts it: in MaterialApp.builder,
// above the Navigator, with the app underneath. Mounting it inside a Scaffold
// hid the missing Material (yellow underlines), the missing Overlay (tooltips),
// a drag layer the content covered, and keyboard focus left with the app.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/player/artwork.dart' show coverPaletteProvider;
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/desktop/player_bar.dart';
import 'package:navivibe/widgets/shell/mini_player_view.dart';

import 'mini_player_fakes.dart';

void main() {
  late List<String> windowCalls;

  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    windowCalls = [];
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowCalls.add(call.method);
          if (call.method == 'getBounds') {
            return {'x': 10.0, 'y': 10.0, 'width': 360.0, 'height': 96.0};
          }
          return false;
        });
  });
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  int drags() => windowCalls.where((m) => m == 'startDragging').length;

  late FakePlayer player;
  late FocusNode appFocus;

  Future<MiniPlayer> openInApp(WidgetTester tester, MiniMode mode) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = MiniPlayer.sizeFor(mode);
    addTearDown(tester.view.reset);
    final mini = MiniPlayer(
      window: MemWindow(),
      store: MemStore(MiniPrefs(mode: mode)),
    );
    player = FakePlayer(true);
    appFocus = FocusNode();
    addTearDown(appFocus.dispose);
    final List<Override> overrides = [
      playerProvider.overrideWith((ref) => player),
      settingsProvider.overrideWith((ref) => FakeSettings()),
      subsonicServiceProvider.overrideWithValue(FakeSubsonic()),
      catalogSongProvider.overrideWith((ref, id) => null),
      lyricsControllerProvider.overrideWith(() => FakeLyrics(null)),
      coverPaletteProvider(
        's1',
      ).overrideWithValue(const AsyncData(AlbumPalette.fallback)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            theme: AppTheme.build(AppThemeTokens.fallback),
            builder: (context, child) =>
                MiniPlayerHost(controller: mini, child: child!),
            home: Scaffold(
              // Something in the app holds the keyboard, as it does in use.
              body: Focus(
                focusNode: appFocus,
                autofocus: true,
                child: const Text('the app'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    mini.active.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return mini;
  }

  Future<void> mouseDrag(WidgetTester tester, Offset from, Offset by) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(from + by * (i / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final mode in MiniMode.values) {
    group('${mode.name} shape in the app', () {
      testWidgets('builds with a real text style and no errors', (
        tester,
      ) async {
        await openInApp(tester, mode);
        expect(tester.takeException(), isNull);
        for (final text in tester.widgetList<RichText>(
          find.descendant(
            of: find.byType(MiniPlayerView),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            text.text.style?.decoration ?? TextDecoration.none,
            TextDecoration.none,
            reason: '"${text.text.toPlainText()}" has the debug underline',
          );
        }
      });

      testWidgets('hovering a button shows its tooltip', (tester) async {
        await openInApp(tester, mode);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byTooltip('Next (Ctrl+→)')));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Next (Ctrl+→)'), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 2));
      });

      testWidgets('the cover drags the window', (tester) async {
        await openInApp(tester, mode);
        await mouseDrag(
          tester,
          mode == MiniMode.bar ? const Offset(40, 40) : const Offset(180, 110),
          const Offset(30, 12),
        );
        expect(drags(), 1);
      });

      testWidgets('the title drags the window', (tester) async {
        await openInApp(tester, mode);
        await mouseDrag(
          tester,
          tester.getTopLeft(find.text('Thaniye')) + const Offset(8, 8),
          const Offset(0, 25),
        );
        expect(drags(), 1);
      });

      testWidgets('dragging the seek bar seeks and never moves the window', (
        tester,
      ) async {
        await openInApp(tester, mode);
        final bar = tester.getRect(find.byType(DesktopSeekBar));
        // The strip's bar hangs past the window's edge; stay on what shows.
        final y = mode == MiniMode.bar ? 92.0 : bar.center.dy;
        await mouseDrag(tester, Offset(bar.center.dx, y), const Offset(40, 0));
        expect((player.player as FakeAudio).seeks, isNotEmpty);
        await mouseDrag(tester, Offset(bar.center.dx, y), const Offset(0, -30));
        expect(drags(), 0);
      });

      testWidgets('dragging from a button does not move the window', (
        tester,
      ) async {
        await openInApp(tester, mode);
        for (final tip in ['Next (Ctrl+→)', 'Favorite (L)', 'Keep on top']) {
          final f = find.byTooltip(
            tip == 'Keep on top' ? 'Stop keeping on top' : tip,
          );
          await mouseDrag(tester, tester.getCenter(f), const Offset(0, 20));
        }
        expect(drags(), 0);
      });

      testWidgets('a button acts at once, and a shaky click still counts', (
        tester,
      ) async {
        await openInApp(tester, mode);
        final at = tester.getCenter(find.byTooltip('Next (Ctrl+→)'));
        final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
        await g.moveBy(const Offset(0, 1));
        await g.up();
        await tester.pump();
        expect(player.nexts, 1);
        expect(drags(), 0);
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('a double-click on the cover switches shape', (tester) async {
        final mini = await openInApp(tester, mode);
        final at = mode == MiniMode.bar
            ? const Offset(40, 40)
            : const Offset(180, 110);
        await tester.tapAt(at, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(at, kind: PointerDeviceKind.mouse);
        expect(mini.mode.value, isNot(mode));
        expect(drags(), 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('two slow clicks do not switch shape', (tester) async {
        final mini = await openInApp(tester, mode);
        final at = mode == MiniMode.bar
            ? const Offset(40, 40)
            : const Offset(180, 110);
        await tester.tapAt(at, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tapAt(at, kind: PointerDeviceKind.mouse);
        expect(mini.mode.value, mode);
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('takes the keyboard from the app underneath', (tester) async {
        await openInApp(tester, mode);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(player.toggles, 1);
      });
    });
  }
}
