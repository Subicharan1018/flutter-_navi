import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/ui/grouped_list.dart';
import 'package:navivibe/widgets/ui/media.dart';
import 'package:navivibe/widgets/ui/navi_icon_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: Scaffold(body: Center(child: child)),
    );

/// The ring is a foreground-decorated box with a border; count them.
Finder _ring() => find.byWidgetPredicate((w) => w is DecoratedBox && w.position == DecorationPosition.foreground && (w.decoration as BoxDecoration).border != null);

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);

  group('focus ring follows the input device', () {
    testWidgets('a mouse click does not draw the ring; Tab does', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(NaviIconButton(glyph: NaviGlyph.gear, tooltip: 'Go', onTap: () => taps++)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(NaviIconButton)));
      await mouse.down(tester.getCenter(find.byType(NaviIconButton)));
      await mouse.up();
      await tester.pump();
      expect(taps, 1);
      expect(_ring(), findsNothing, reason: 'clicking is not keyboard navigation');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_ring(), findsOneWidget, reason: 'the keyboard brings the ring back');
    });
  });

  group('HoverPlayDisc', () {
    testWidgets('is hidden until hovered, and a focused disc shows without hover', (tester) async {
      var played = 0;
      await tester.pumpWidget(_host(HoverPlayDisc(visible: false, onPlay: () => played++, label: 'Play Mix')));
      double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
      expect(opacity(), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(opacity(), 1, reason: 'keyboard focus reveals the disc');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(played, 1);
    });
  });

  group('flat toggle', () {
    testWidgets('desktop toggle is a square-cornered switch that flips', (tester) async {
      var on = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (c, set) => GroupedSwitchRow(title: 'Crossfade', value: on, onChanged: (v) => set(() => on = v)),
      )));
      expect(find.byType(CupertinoSwitch), findsNothing);
      await tester.tap(find.byType(NaviPressable));
      await tester.pump();
      expect(on, isTrue);
    });
  });

  group('text floor', () {
    testWidgets('caption sizes never go under 12 on desktop', (tester) async {
      late TextStyle c1, c2;
      await tester.pumpWidget(_host(Builder(builder: (context) {
        final t = ThemeTokens.of(context);
        c1 = t.caption1;
        c2 = t.caption2;
        return const SizedBox();
      })));
      expect(c1.fontSize, greaterThanOrEqualTo(12));
      expect(c2.fontSize, greaterThanOrEqualTo(12));
    });
  });

  test('hover and selected tokens are distinct washes', () {
    final t = AppThemeTokens.fallback;
    expect(t.selected.a, greaterThan(t.hover.a));
  });
}
