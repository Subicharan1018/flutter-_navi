import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/month/ui/story/story_pager.dart';
import 'package:navivibe/screens/stats/widgets/heat_grid.dart';
import 'package:navivibe/widgets/motion/number_roll.dart';
import 'package:navivibe/widgets/motion/reveal.dart';

Widget _host(Widget child, {bool reduced = false}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduced),
        child: child,
      ),
    );

StoryPager _pager({VoidCallback? onClose}) => StoryPager(
      onClose: onClose,
      pages: [
        for (final label in ['one', 'two', 'three'])
          StoryPage(duration: const Duration(seconds: 2), builder: (_, _) => Center(child: Text(label))),
      ],
    );

void main() {
  group('NumberRoll', () {
    testWidgets('rolls digits, then settles on the formatted text', (tester) async {
      await tester.pumpWidget(_host(const NumberRoll(value: 4821, style: TextStyle(fontSize: 20))));
      await tester.pump(const Duration(milliseconds: 300));
      // Mid-roll: every digit is a strip of 20 numbers, not the final text.
      expect(find.text('4821'), findsNothing);
      expect(find.bySemanticsLabel('4821'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('4821'), findsOneWidget);
    });

    testWidgets('keeps separators fixed while only digits roll', (tester) async {
      await tester.pumpWidget(_host(NumberRoll(value: 90, format: (v) => '${v}h', style: const TextStyle(fontSize: 20))));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('h'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('90h'), findsOneWidget);
    });

    testWidgets('reduced motion shows the final number on the first frame', (tester) async {
      await tester.pumpWidget(_host(const NumberRoll(value: 4821, style: TextStyle(fontSize: 20)), reduced: true));
      expect(find.text('4821'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('rolls to a new value when it changes', (tester) async {
      await tester.pumpWidget(_host(const NumberRoll(value: 10, style: TextStyle(fontSize: 20))));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(const NumberRoll(value: 25, style: TextStyle(fontSize: 20))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('25'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('25'), findsOneWidget);
    });
  });

  group('StoryPager', () {
    testWidgets('right tap advances, left tap goes back', (tester) async {
      await tester.pumpWidget(_host(_pager()));
      expect(find.text('one'), findsOneWidget);
      await tester.tapAt(const Offset(600, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('two'), findsOneWidget);
      await tester.tapAt(const Offset(40, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('advances by itself when a card finishes, and stops on the last', (tester) async {
      await tester.pumpWidget(_host(_pager()));
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('two'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('three'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('three'), findsOneWidget);
    });

    testWidgets('press and hold pauses the card', (tester) async {
      await tester.pumpWidget(_host(_pager()));
      final hold = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 600)); // long press recognised
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('one'), findsOneWidget);
      await hold.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('two'), findsOneWidget);
    });

    testWidgets('reduced motion: no auto-advance, cards get a finished clock', (tester) async {
      double? clock;
      await tester.pumpWidget(_host(
        StoryPager(pages: [
          StoryPage(builder: (_, p) {
            clock = p.value;
            return const Text('one');
          }),
          StoryPage(builder: (_, _) => const Text('two')),
        ]),
        reduced: true,
      ));
      expect(clock, 1);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('one'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tapAt(const Offset(600, 300));
      await tester.pump();
      expect(find.text('two'), findsOneWidget);
    });

    testWidgets('close button calls onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(_host(_pager(onClose: () => closed = true)));
      await tester.tapAt(const Offset(765, 30));
      await tester.pump();
      expect(closed, isTrue);
    });
  });

  group('motion primitives', () {
    testWidgets('HeatGrid reaches its finished state and stops animating', (tester) async {
      await tester.pumpWidget(_host(Center(child: SizedBox(width: 300, child: HeatGrid(values: List.filled(20, 1.0), rows: 2)))));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Reveal shows its child at once under reduced motion', (tester) async {
      await tester.pumpWidget(_host(const Reveal(child: Text('hello')), reduced: true));
      expect(find.text('hello'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
