import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/player/player_controls.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/tv_frame.dart';
import 'package:navivibe/widgets/shell/tv_shell.dart';
import 'package:navivibe/widgets/ui/grouped_list.dart';

/// What the D-pad can and can't do on a TV. A real remote is simulated with
/// key events; `PlatformUtils.debugTvOverride` makes the app believe it is on one.
Widget _app(Widget child, {Size size = const Size(960, 540), double dpr = 2}) => ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: dpr),
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            builder: (context, c) => TvFrame(child: c!),
            home: Scaffold(body: child),
          ),
        ),
      ),
    );


Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  phoneAndDesktopUnchanged();
  setUp(() => PlatformUtils.debugTvOverride = true);
  tearDown(() => PlatformUtils.debugTvOverride = null);

  testWidgets('from the rail Right enters the content and Left comes back', (tester) async {
    final selected = FocusNode(debugLabel: 'rail-selected');
    final rail = FocusNode(debugLabel: 'rail', skipTraversal: true, canRequestFocus: false);
    final log = <String>[];
    // The same arrangement TvShell uses: a plain Focus (never a FocusScope,
    // which would trap the D-pad) around the rail, content beside it.
    await tester.pumpWidget(_app(
      Row(
        children: [
          FocusTraversalGroup(
            child: Focus(
              focusNode: rail,
              child: TvRail(tab: AppTab.home, onSelect: (t) => log.add('tab ${t.name}'), selectedNode: selected),
            ),
          ),
          Expanded(
            child: FocusTraversalGroup(
              child: ListView(
                children: [
                  for (final name in ['play', 'cover1', 'cover2'])
                    CupertinoClickable(
                      onTap: () => log.add(name),
                      child: SizedBox(height: 80, child: Center(child: Text(name))),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
    await tester.pump();
    expect(selected.hasPrimaryFocus, isTrue, reason: 'the current tab starts focused');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(rail.hasFocus, isFalse, reason: 'Right must leave the rail');
    await _press(tester, LogicalKeyboardKey.select);
    expect(log, hasLength(1), reason: 'and land on something activatable');
    final first = log.single;

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(log, hasLength(2));
    expect(log.last, isNot(first), reason: 'Down moves to the next item');

    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(rail.hasFocus, isTrue, reason: 'Left returns to the rail');
  });

  testWidgets('every rail destination is reachable with Down and Select switches tab', (tester) async {
    final log = <AppTab>[];
    await tester.pumpWidget(_app(
      Row(children: [TvRail(tab: AppTab.home, onSelect: log.add), const Expanded(child: SizedBox())]),
    ));
    await tester.pump();
    for (var i = 0; i < AppTab.values.length; i++) {
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(log.toSet(), AppTab.values.toSet());
  });

  testWidgets('the rail fits at the 1280×720 canvas and at a short 1280×540 one', (tester) async {
    for (final size in const [Size(960, 540), Size(1280, 720), Size(640, 360)]) {
      await tester.pumpWidget(_app(
        Row(children: [TvRail(tab: AppTab.home, onSelect: (_) {}), const Expanded(child: SizedBox())]),
        size: size,
        dpr: 1920 / size.width,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow at $size');
      final canvas = TvFrame.canvasFor(size);
      expect(canvas.width, 1280);
      expect(canvas.height, closeTo(720, 1));
      final settings = tester.getRect(find.text('Settings'));
      expect(settings.bottom, lessThanOrEqualTo(canvas.height), reason: 'Settings is on screen at $size');
    }
  });

  testWidgets('a Settings row can be selected with the remote', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(
      ListView(children: [GroupedSection(children: [GroupedRow(title: 'Sign in another device', onTap: () => taps++)])]),
    ));
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowDown); // first focus lands on the row
    await _press(tester, LogicalKeyboardKey.select);
    expect(taps, 1);
  });

  testWidgets('a text field does not trap the D-pad and opens its keyboard only on Select', (tester) async {
    final a = TextEditingController(), b = TextEditingController();
    final fa = FocusNode(debugLabel: 'a'), fb = FocusNode(debugLabel: 'b');
    await tester.pumpWidget(_app(
      Column(children: [
        GroupedTextFieldRow(title: 'One', controller: a, focusNode: fa, autofocus: true),
        GroupedTextFieldRow(title: 'Two', controller: b, focusNode: fb),
      ]),
    ));
    await tester.pump();
    expect(fa.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'focus alone must not raise the keyboard');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(fb.hasPrimaryFocus, isTrue, reason: 'Down leaves a text field');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(fa.hasPrimaryFocus, isTrue);

    await _press(tester, LogicalKeyboardKey.select);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue, reason: 'Select starts editing');
  });

  testWidgets('a slider takes Left and Right from the remote and commits the change', (tester) async {
    final changes = <double>[];
    await tester.pumpWidget(_app(
      Column(children: [
        ElasticTrack(
          value: 0.5,
          activeColor: Colors.white,
          inactiveColor: Colors.grey,
          semanticLabel: 'Playback position',
          onChanged: (_) {},
          onChangeEnd: changes.add,
        ),
      ]),
    ));
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowDown); // reach the slider
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(changes, hasLength(2));
    expect(changes.first, closeTo(0.53, 0.001));
    expect(changes.last, closeTo(0.47, 0.001));
  });

  testWidgets('Back (Escape) from a focused control is not swallowed by the focus ring', (tester) async {
    var popped = false;
    await tester.pumpWidget(_app(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => popped = true,
        child: CupertinoClickable(onTap: () {}, autofocus: true, child: const SizedBox(width: 80, height: 80)),
      ),
    ));
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    expect(popped, isTrue);
  });

  test('the TV canvas keeps the screen aspect ratio', () {
    for (final real in const [Size(960, 540), Size(1280, 720), Size(1366, 768), Size(960, 540 * 1.1)]) {
      final c = TvFrame.canvasFor(real);
      expect(c.width, TvFrame.designWidth);
      expect(c.width / c.height, closeTo(real.width / real.height, 0.001));
    }
  });
}

/// Phone and Windows are untouched by the TV canvas: same size, same density,
/// same text scale in, same out.
void phoneAndDesktopUnchanged() {
  for (final c in const [
    (Size(360, 800), 3.0),
    (Size(412, 915), 2.625),
    (Size(1280, 800), 1.0),
    (Size(960, 540), 2.0), // a 960x540@2 window that is NOT a TV
  ]) {
    testWidgets('TvFrame leaves ${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2} alone off a TV', (tester) async {
      PlatformUtils.debugTvOverride = false;
      MediaQueryData? seen;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: c.$1, devicePixelRatio: c.$2),
        child: TvFrame(
          child: Builder(builder: (context) {
            seen = MediaQuery.of(context);
            return const SizedBox();
          }),
        ),
      ));
      expect(seen!.size, c.$1);
      expect(seen!.devicePixelRatio, c.$2);
      expect(seen!.textScaler, TextScaler.noScaling);
    });
  }
}
