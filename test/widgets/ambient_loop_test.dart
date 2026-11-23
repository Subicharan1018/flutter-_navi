import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/widgets/motion/ambient_loop.dart';

Widget _host({required bool full, Widget? child, bool tickers = true, double offset = 0}) => MotionScope(
  full: full,
  child: MaterialApp(
    home: Scaffold(
      body: TickerMode(
        enabled: tickers,
        child: Stack(
          children: [
            Positioned(
              top: offset,
              left: 0,
              width: 100,
              height: 100,
              child: AmbientLoop(period: const Duration(seconds: 1), builder: (context, phase) => Text('$phase')),
            ),
          ],
        ),
      ),
    ),
  ),
);

AmbientLoopState _state(WidgetTester t) => t.state<AmbientLoopState>(find.byType(AmbientLoop));

void main() {
  setUp(() => AmbientLoop.debugForceRun = true);
  tearDown(() => AmbientLoop.debugForceRun = false);

  testWidgets('runs while visible and Motion is Full', (tester) async {
    await tester.pumpWidget(_host(full: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isTrue);
  });

  testWidgets('stays still under Reduced motion', (tester) async {
    await tester.pumpWidget(_host(full: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isFalse);
  });

  testWidgets('stops when Motion is switched to Reduced', (tester) async {
    await tester.pumpWidget(_host(full: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isTrue);
    await tester.pumpWidget(_host(full: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isFalse);
  });

  testWidgets('stops when its route stops ticking', (tester) async {
    await tester.pumpWidget(_host(full: true));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(_host(full: true, tickers: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isFalse);
  });

  testWidgets('stops when scrolled off screen', (tester) async {
    await tester.pumpWidget(_host(full: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isTrue);
    await tester.pumpWidget(_host(full: true, offset: 5000));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isFalse);
  });

  testWidgets('stops when the app goes to the background', (tester) async {
    await tester.pumpWidget(_host(full: true));
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).running, isTrue);
  });

  testWidgets('repaints at about 30 fps, not every frame', (tester) async {
    await tester.pumpWidget(_host(full: true));
    var changes = 0;
    var last = '';
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = (tester.widget(find.byType(Text)) as Text).data!;
      if (now != last) changes++;
      last = now;
    }
    expect(changes, lessThanOrEqualTo(34));
    expect(changes, greaterThan(15));
  });
}
