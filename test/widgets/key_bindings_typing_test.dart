import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/keyboard_shortcuts.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/share/share_card.dart';

void main() {
  group('keys in a text field', () {
    late List<String> fired;
    late FocusNode field;
    late FocusNode page;

    Future<void> pump(WidgetTester tester) async {
      fired = [];
      field = FocusNode();
      page = FocusNode();
      addTearDown(field.dispose);
      addTearDown(page.dispose);
      await tester.pumpWidget(CupertinoApp(
        home: NaviKeyBindings(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyR): () => fired.add('repeat'),
            const SingleActivator(LogicalKeyboardKey.keyS): () => fired.add('shuffle'),
            const SingleActivator(LogicalKeyboardKey.space): () => fired.add('play'),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => fired.add('seek'),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => fired.add('search'),
          },
          child: Column(children: [
            CupertinoTextField(focusNode: field),
            Focus(focusNode: page, child: const SizedBox(height: 10)),
          ]),
        ),
      ));
    }

    testWidgets('letters, space and arrows reach the focused field', (tester) async {
      await pump(tester);
      field.requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      expect(fired, isEmpty);
    });

    testWidgets('a key in a field is not reported as handled', (tester) async {
      await pump(tester);
      field.requestFocus();
      await tester.pump();
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      expect(handled, isFalse);
    });

    testWidgets('the same keys are shortcuts outside a field', (tester) async {
      await pump(tester);
      page.requestFocus();
      await tester.pump();
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      expect(handled, isTrue);
      expect(fired, ['repeat']);
    });

    testWidgets('Ctrl shortcuts still work while typing', (tester) async {
      await pump(tester);
      field.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(fired, ['search']);
    });
  });

  group('share card', () {
    for (final scale in [1.0, 1.5]) {
      testWidgets('a long title and subtitle fit at text scale $scale', (tester) async {
        await tester.pumpWidget(CupertinoApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: Builder(builder: (context) {
                ThemeTokens.of(context);
                return const ShareCard(
                  kind: ShareKind.song,
                  title: 'Are You Ready? (House/EDM Set) with a title that runs on for a very long way indeed',
                  subtitle: 'An artist with a long name, and another one, and one more',
                );
              }),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('Song on NaviVibe'), findsOneWidget);
      });
    }
  });
}
