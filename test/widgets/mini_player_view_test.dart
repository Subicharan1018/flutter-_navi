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
import 'package:navivibe/widgets/shell/mini_player_view.dart';

import 'mini_player_fakes.dart';

MiniPlayer _mini(MiniMode mode, {MiniWindow? window}) => MiniPlayer(
  window: window ?? MemWindow(),
  store: MemStore(MiniPrefs(mode: mode)),
);

Widget _app(
  Widget child, {
  bool withSong = true,
  String? lyric,
  double textScale = 1,
}) {
  final List<Override> overrides = [
    playerProvider.overrideWith((ref) => FakePlayer(withSong)),
    settingsProvider.overrideWith((ref) => FakeSettings()),
    subsonicServiceProvider.overrideWithValue(FakeSubsonic()),
    catalogSongProvider.overrideWith((ref, id) => null),
    lyricsControllerProvider.overrideWith(() => FakeLyrics(lyric)),
    coverPaletteProvider(
      's1',
    ).overrideWithValue(const AsyncData(AlbumPalette.fallback)),
  ];
  return PointerAnchor(
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        ),
        home: child,
      ),
    ),
  );
}

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() => PointerAnchor.reset());

  Future<void> sized(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Future<MiniPlayer> open(
    WidgetTester tester,
    MiniMode mode, {
    bool withSong = true,
    String? lyric,
    double textScale = 1,
    VoidCallback? onReturn,
  }) async {
    await sized(tester, MiniPlayer.sizeFor(mode));
    final mini = _mini(mode);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: MiniPlayerView(onReturn: onReturn ?? () {}, controller: mini),
        ),
        withSong: withSong,
        lyric: lyric,
        textScale: textScale,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return mini;
  }

  FakePlayer fake(WidgetTester t) =>
      ProviderScope.containerOf(
            t.element(find.byType(MiniPlayerView)),
          ).read(playerProvider.notifier)
          as FakePlayer;

  for (final mode in MiniMode.values) {
    group('${mode.name} shape', () {
      testWidgets(
        'shows the song, the time and the controls, and fits its window',
        (tester) async {
          var returned = 0;
          await open(tester, mode, onReturn: () => returned++);
          expect(tester.takeException(), isNull);
          expect(find.text('Thaniye'), findsOneWidget);
          expect(find.text('Anirudh'), findsOneWidget);
          final time = mode == MiniMode.bar
              ? find.text('1:00 / 4:00')
              : find.text('1:00');
          expect(time, findsOneWidget);
          for (final tip in [
            'Previous (Ctrl+←)',
            'Next (Ctrl+→)',
            'Favorite (L)',
            'Stop keeping on top',
            'Back to full player',
          ]) {
            expect(find.byTooltip(tip), findsOneWidget, reason: tip);
          }
          expect(
            find.byTooltip(
              mode == MiniMode.bar ? 'Show the cover' : 'Show the strip',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Back to full player'));
          expect(returned, 1);
        },
      );

      testWidgets('does not overflow at text scale 1.3', (tester) async {
        await open(
          tester,
          mode,
          textScale: 1.3,
          lyric:
              'a line that is quite a bit longer than the window is wide, to prove it ends cleanly',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Thaniye'), findsOneWidget);
      });

      testWidgets('the controls drive the player', (tester) async {
        await open(tester, mode);
        await tester.tap(find.bySemanticsLabel('Pause'));
        await tester.tap(find.byTooltip('Next (Ctrl+→)'));
        await tester.tap(find.byTooltip('Previous (Ctrl+←)'));
        await tester.tap(find.byTooltip('Favorite (L)'));
        final f = fake(tester);
        expect([f.toggles, f.nexts, f.prevs], [1, 1, 1]);
        expect(f.stars, ['s1']);
      });

      testWidgets('the wheel changes the volume and a toast names it', (
        tester,
      ) async {
        await open(tester, mode);
        final audio = fake(tester).player as FakeAudio;
        final pointer = TestPointer(1, PointerDeviceKind.mouse)
          ..hover(tester.getCenter(find.byType(MiniPlayerView)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(audio.vol, closeTo(0.55, 1e-9));
        expect(find.text('55'), findsOneWidget);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        expect(audio.vol, closeTo(0.45, 1e-9));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('45'), findsNothing, reason: 'the toast leaves');
      });

      testWidgets('Space, arrows, L and Esc work from the keyboard', (
        tester,
      ) async {
        var returned = 0;
        await open(tester, mode, onReturn: () => returned++);
        final f = fake(tester);
        final audio = f.player as FakeAudio;
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(f.toggles, 1);
        expect(audio.seeks, [const Duration(seconds: 65)]);
        expect(audio.vol, closeTo(0.55, 1e-9));
        expect(f.stars, ['s1']);
        expect(f.nexts, 1);
        expect(returned, 1);
        await tester.pump(const Duration(seconds: 2));
      });

      testWidgets('the live lyric line shows while it is sung', (tester) async {
        await open(tester, mode, lyric: 'line one');
        expect(find.text('line one'), findsOneWidget);
      });

      testWidgets(
        'with nothing playing it says so and still offers the way back',
        (tester) async {
          await open(tester, mode, withSong: false);
          expect(tester.takeException(), isNull);
          expect(find.text('Nothing playing'), findsOneWidget);
          expect(find.byTooltip('Back to full player'), findsOneWidget);
        },
      );

      testWidgets('with reduced motion it renders without animating in', (
        tester,
      ) async {
        await sized(tester, MiniPlayer.sizeFor(mode));
        final mini = _mini(mode);
        await tester.pumpWidget(
          _app(
            MediaQuery(
              data: MediaQueryData(
                disableAnimations: true,
                size: MiniPlayer.sizeFor(mode),
              ),
              child: Scaffold(
                body: MiniPlayerView(onReturn: () {}, controller: mini),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Thaniye'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('the shape and pin buttons act on the window', (tester) async {
    final w = MemWindow();
    await sized(tester, MiniPlayer.barSize);
    final mini = _mini(MiniMode.bar, window: w);
    await mini.enter();
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: MiniPlayerView(onReturn: () {}, controller: mini),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Stop keeping on top'));
    await tester.pump();
    expect(w.onTop, isFalse);
    expect(mini.pinned.value, isFalse);
    await tester.tap(find.byTooltip('Show the cover'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(mini.mode.value, MiniMode.cover);
    expect(w.rect.size, MiniPlayer.coverSize);
    expect(find.byTooltip('Show the strip'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'the host keeps the app mounted underneath and swaps the view in and out',
    (tester) async {
      await sized(tester, MiniPlayer.barSize);
      final mini = _mini(MiniMode.bar);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: MiniPlayerHost(
              controller: mini,
              child: const Text('the app'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Thaniye'), findsNothing);
      mini.active.value = true;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('the app'), findsNothing, reason: 'offstage');
      expect(
        find.text('the app', skipOffstage: false),
        findsOneWidget,
        reason: 'state is kept',
      );
      expect(find.text('Thaniye'), findsOneWidget);
      mini.active.value = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('the app'), findsOneWidget);
    },
  );
}
