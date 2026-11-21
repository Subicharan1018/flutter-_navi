import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/marquee.dart';
import 'package:navivibe/player/fitting_title.dart';

const _long = 'A very long film title that cannot possibly fit in this narrow row (From "Some Film")';

Widget _host(String text, {bool reduce = false, double width = 200}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Center(
          child: SizedBox(width: width, height: 28, child: FittingTitle(text: text, style: const TextStyle(fontSize: 22))),
        ),
      ),
    );

void main() {
  testWidgets('a title that fits is plain text and never scrolls', (tester) async {
    await tester.pumpWidget(_host('Short'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Marquee), findsNothing);
    expect(find.text('Short'), findsOneWidget);
  });

  testWidgets('a long title rests as an ellipsis, scrolls twice, then settles back', (tester) async {
    await tester.pumpWidget(_host(_long));
    // At rest it is a finished-looking ellipsis, not a mid-letter cut.
    final rest = tester.widget<Text>(find.text(_long));
    expect(rest.overflow, TextOverflow.ellipsis);
    expect(find.byType(Marquee), findsNothing);

    await tester.pump(FittingTitle.beat + const Duration(milliseconds: 100));
    expect(find.byType(Marquee), findsOneWidget);

    // Two passes of (text + gap) / velocity plus the rests between, with slack.
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(find.byType(Marquee), findsNothing);
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
  });

  testWidgets('a new song restarts the beat', (tester) async {
    await tester.pumpWidget(_host(_long));
    await tester.pump(FittingTitle.beat + const Duration(milliseconds: 100));
    expect(find.byType(Marquee), findsOneWidget);
    await tester.pumpWidget(_host('$_long again'));
    expect(find.byType(Marquee), findsNothing);
    await tester.pump(FittingTitle.beat + const Duration(milliseconds: 100));
    expect(find.byType(Marquee), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('reduced motion never scrolls', (tester) async {
    await tester.pumpWidget(_host(_long, reduce: true));
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(Marquee), findsNothing);
  });
}
