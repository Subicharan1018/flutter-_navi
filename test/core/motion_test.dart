import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/widgets/ui/heart_burst.dart';

Widget _app(Widget child, {MotionLevel level = MotionLevel.full}) => ThemeTokens(
      tokens: AppThemeTokens.fallback,
      child: MaterialApp(
        builder: (context, c) => MotionScope.resolve(
          level: level,
          systemReduced: MediaQuery.disableAnimationsOf(context),
          child: c!,
        ),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(seenEntrances.clear);

  group('MotionScope', () {
    testWidgets('Full allows motion, Reduced and system-reduced do not', (tester) async {
      late BuildContext ctx;
      Widget probe(MotionLevel l, {bool system = false}) => MediaQuery(
            data: MediaQueryData(disableAnimations: system),
            child: MotionScope.resolve(
              level: l,
              systemReduced: system,
              child: Builder(builder: (c) {
                ctx = c;
                return const SizedBox();
              }),
            ),
          );
      await tester.pumpWidget(probe(MotionLevel.full));
      expect(ctx.motionFull, isTrue);
      await tester.pumpWidget(probe(MotionLevel.reduced));
      expect(ctx.motionFull, isFalse);
      await tester.pumpWidget(probe(MotionLevel.full, system: true));
      expect(ctx.motionFull, isFalse);
    });

  });

  group('Entrance', () {
    Widget list(MotionLevel level) => _app(
          Column(children: [
            for (var i = 0; i < 3; i++) Entrance(group: 'g', index: i, child: Text('row$i')),
          ]),
          level: level,
        );

    testWidgets('first appearance slides and fades in, then rests', (tester) async {
      await tester.pumpWidget(list(MotionLevel.full));
      final first = tester.widget<FadeTransition>(find.ancestor(of: find.text('row2'), matching: find.byType(FadeTransition)).first);
      expect(first.opacity.value, 0);
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(find.ancestor(of: find.text('row2'), matching: find.byType(FadeTransition)).first).opacity.value, 1);
    });

    testWidgets('does not play again for a group already seen', (tester) async {
      await tester.pumpWidget(list(MotionLevel.full));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(list(MotionLevel.full));
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.text('row0'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 1);
    });

    testWidgets('Reduced motion shows rows at rest immediately', (tester) async {
      await tester.pumpWidget(list(MotionLevel.reduced));
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.text('row1'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('PlayPauseMorph', () {
    test('points interpolate between play and pause', () {
      final play = PlayPausePainter.pointsAt(0);
      final pause = PlayPausePainter.pointsAt(1);
      final mid = PlayPausePainter.pointsAt(0.5);
      expect(play, isNot(equals(pause)));
      expect(mid[0].dx, closeTo((play[0].dx + pause[0].dx) / 2, 1e-9));
      // The right quad starts as a sliver (triangle tip) and ends as a bar.
      expect(play[5], play[6]);
      expect(pause[5], isNot(pause[6]));
    });

    testWidgets('animates when Full, snaps when Reduced', (tester) async {
      Widget w(bool playing, MotionLevel l) =>
          _app(PlayPauseMorph(playing: playing, size: 40, color: Colors.white), level: l);
      await tester.pumpWidget(w(false, MotionLevel.full));
      await tester.pumpWidget(w(true, MotionLevel.full));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();

      await tester.pumpWidget(w(false, MotionLevel.reduced));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('Shimmer and Drift', () {
    testWidgets('run when Full', (tester) async {
      await tester.pumpWidget(_app(const Column(children: [
        Shimmer(child: SizedBox(width: 50, height: 10)),
        Drift(child: SizedBox(width: 50, height: 50)),
      ])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('are still when Reduced', (tester) async {
      await tester.pumpWidget(_app(
        const Column(children: [
          Shimmer(child: SizedBox(width: 50, height: 10)),
          Drift(child: SizedBox(width: 50, height: 50)),
        ]),
        level: MotionLevel.reduced,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('HeartBurst', () {
    Widget w(bool on, MotionLevel l) => _app(
          HeartBurst(active: on, color: Colors.white, child: const SizedBox(width: 40, height: 40)),
          level: l,
        );

    testWidgets('bursts when turned on, not on first build or turning off', (tester) async {
      await tester.pumpWidget(w(true, MotionLevel.full));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(w(false, MotionLevel.full));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(w(true, MotionLevel.full));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('does nothing when Reduced', (tester) async {
      await tester.pumpWidget(w(false, MotionLevel.reduced));
      await tester.pumpWidget(w(true, MotionLevel.reduced));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('PressScale and Pulse', () {
    testWidgets('PressScale dips under a pointer only when Full', (tester) async {
      for (final level in MotionLevel.values) {
        await tester.pumpWidget(_app(const PressScale(child: SizedBox(key: Key('x'), width: 80, height: 80)), level: level));
        final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('x'))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final scale = tester.widget<ScaleTransition>(find.descendant(of: find.byType(PressScale), matching: find.byType(ScaleTransition)).first).scale.value;
        expect(scale, level == MotionLevel.full ? lessThan(1) : 1);
        await g.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Pulse pops on change when Full, not when Reduced', (tester) async {
      Widget w(int n, MotionLevel l) => _app(Pulse(trigger: n, child: const SizedBox(width: 10, height: 10)), level: l);
      await tester.pumpWidget(w(0, MotionLevel.full));
      await tester.pumpWidget(w(1, MotionLevel.full));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      await tester.pumpWidget(w(1, MotionLevel.reduced));
      await tester.pumpWidget(w(2, MotionLevel.reduced));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
