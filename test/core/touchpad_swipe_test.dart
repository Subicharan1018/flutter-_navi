import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/touchpad_swipe.dart';

TouchpadSwipe _run(List<(int ms, double dx, double dy)> steps) {
  final r = TouchpadSwipeRecogniser();
  r.start(Duration.zero);
  for (final (ms, dx, dy) in steps) {
    r.update(Duration(milliseconds: ms), Offset(dx, dy));
  }
  return r.end();
}

void main() {
  group('recogniser', () {
    test('a quick two-finger swipe to the right goes back', () {
      expect(_run([(80, 120, 4), (160, 260, 10)]), TouchpadSwipe.back);
    });

    test('a quick swipe to the left goes forward', () {
      expect(_run([(80, -120, 4), (160, -260, 10)]), TouchpadSwipe.forward);
    });

    test('a slow drag is scrolling, not a swipe', () {
      expect(_run([(500, 100, 0), (1200, 300, 0)]), TouchpadSwipe.none);
    });

    test('a short flick does nothing', () {
      expect(_run([(60, 60, 0), (120, 110, 0)]), TouchpadSwipe.none);
    });

    test('a mostly vertical swipe is a scroll', () {
      expect(_run([(80, 120, 150), (160, 260, 300)]), TouchpadSwipe.none);
    });

    test('a new gesture starts from zero', () {
      final r = TouchpadSwipeRecogniser();
      r.start(Duration.zero);
      r.update(const Duration(milliseconds: 100), const Offset(300, 0));
      expect(r.end(), TouchpadSwipe.back);
      r.start(const Duration(seconds: 5));
      r.update(const Duration(seconds: 5, milliseconds: 50), const Offset(20, 0));
      expect(r.end(), TouchpadSwipe.none);
    });
  });

  testWidgets('the listener turns a touchpad swipe into back', (tester) async {
    var swipes = <TouchpadSwipe>[];
    await tester.pumpWidget(MaterialApp(home: TouchpadSwipeListener(onSwipe: swipes.add, child: const SizedBox.expand())));
    final center = tester.getCenter(find.byType(TouchpadSwipeListener));
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pad.panZoomStart(center));
    await tester.sendEventToBinding(pad.panZoomUpdate(center, pan: const Offset(120, 0), timeStamp: const Duration(milliseconds: 80)));
    await tester.sendEventToBinding(pad.panZoomUpdate(center, pan: const Offset(260, 6), timeStamp: const Duration(milliseconds: 160)));
    await tester.sendEventToBinding(pad.panZoomEnd());
    expect(swipes, [TouchpadSwipe.back]);
  });
}
