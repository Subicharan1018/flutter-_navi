// The app's popup: gone on its own, gone with a swipe or a click, never
// stacked, and never over the player controls at the bottom of the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/ui/action_sheet.dart';

void main() {
  const busy = 'Playback is already moving. Try again in a moment.';
  late BuildContext page;
  var undone = 0;

  Future<void> pumpPage(WidgetTester tester) async {
    undone = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          page = context;
          return const SizedBox.expand();
        }),
      ),
    ));
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets [time] pass, then lets the exit animation finish.
  Future<void> pass(WidgetTester tester, Duration time) async {
    await tester.pump(time);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('goes away by itself', () {
    testWidgets('a plain message within 3 seconds', (tester) async {
      await pumpPage(tester);
      showToast(page, busy);
      await enter(tester);
      expect(find.text(busy), findsOneWidget);
      await pass(tester, const Duration(seconds: 3));
      expect(find.text(busy), findsNothing);
    });

    testWidgets('one with an action stays longer, then goes too', (tester) async {
      await pumpPage(tester);
      showToastWithAction(page, 'Removed', actionLabel: 'Undo', onAction: () => undone++);
      await enter(tester);
      await pass(tester, const Duration(seconds: 3));
      expect(find.text('Removed'), findsOneWidget);
      await pass(tester, const Duration(seconds: 4));
      expect(find.text('Removed'), findsNothing);
      expect(undone, 0);
    });

    testWidgets('repeating the same message does not keep it up', (tester) async {
      await pumpPage(tester);
      showToast(page, busy);
      await enter(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        showToast(page, busy);
      }
      await pass(tester, const Duration(seconds: 1));
      expect(find.text(busy), findsNothing);
      await pass(tester, const Duration(seconds: 3));
      expect(find.text(busy), findsNothing, reason: 'no queued copy comes back');
    });
  });

  group('never stacks', () {
    testWidgets('the same message twice is one popup', (tester) async {
      await pumpPage(tester);
      showToast(page, busy);
      showToast(page, busy);
      await enter(tester);
      expect(find.text(busy), findsOneWidget);
    });

    testWidgets('a new message replaces the old one', (tester) async {
      await pumpPage(tester);
      showToast(page, 'First');
      await enter(tester);
      showToast(page, 'Second');
      await enter(tester);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      await pass(tester, const Duration(seconds: 3));
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
    });
  });

  group('can be dismissed', () {
    for (final (name, offset) in [
      ('left', const Offset(-300, 0)),
      ('right', const Offset(300, 0)),
      ('up', const Offset(0, -120)),
    ]) {
      testWidgets('swiped $name', (tester) async {
        await pumpPage(tester);
        showToast(page, busy);
        await enter(tester);
        await tester.fling(find.text(busy), offset, 1200);
        await pass(tester, const Duration(milliseconds: 400));
        expect(find.text(busy), findsNothing);
      });
    }

    testWidgets('clicked', (tester) async {
      await pumpPage(tester);
      showToast(page, busy);
      await enter(tester);
      await tester.tap(find.text(busy));
      await pass(tester, const Duration(milliseconds: 100));
      expect(find.text(busy), findsNothing);
    });

    testWidgets('one with an action too, without running the action', (tester) async {
      await pumpPage(tester);
      showToastWithAction(page, 'Removed', actionLabel: 'Undo', onAction: () => undone++);
      await enter(tester);
      await tester.fling(find.text('Removed'), const Offset(-300, 0), 1200);
      await pass(tester, const Duration(milliseconds: 400));
      expect(find.text('Removed'), findsNothing);
      expect(undone, 0);
    });

    testWidgets('the action runs once and closes it', (tester) async {
      await pumpPage(tester);
      showToastWithAction(page, 'Removed', actionLabel: 'Undo', onAction: () => undone++);
      await enter(tester);
      await tester.tap(find.text('Undo'));
      await pass(tester, const Duration(milliseconds: 100));
      expect(undone, 1);
      expect(find.text('Removed'), findsNothing);
    });
  });

  testWidgets('sits at the top, clear of the player controls', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpPage(tester);
    showToast(page, busy);
    await enter(tester);
    expect(tester.getBottomLeft(find.text(busy)).dy, lessThan(800 / 3));
    await pass(tester, const Duration(seconds: 3));
  });
}
