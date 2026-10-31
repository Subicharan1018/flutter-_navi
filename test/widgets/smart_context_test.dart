import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/providers/catalog_provider.dart' show shortArtists;
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/art/smart_context.dart';
import 'package:navivibe/widgets/ui/dock_ground.dart';

Widget _app(Widget child) => MaterialApp(
      home: ThemeTokens(tokens: AppThemeTokens.fallback, child: Scaffold(body: child)),
    );

void main() {
  test('only server-chosen queues get a Smart context', () {
    expect(SmartContext.of('Smart Shuffle')?.kind, SmartKind.smartShuffle);
    expect(SmartContext.of('Flow')?.kind, SmartKind.flow);
    expect(SmartContext.of('Weekly Mix')?.kind, SmartKind.weekly);
    expect(SmartContext.of('New in Your Library')?.kind, SmartKind.discover);
    expect(SmartContext.of('Favorites'), isNull);
    expect(SmartContext.of(null), isNull);
  });

  testWidgets('the pill names the source and the backdrop crossfades between songs', (tester) async {
    const ctx = SmartContext(SmartKind.smartShuffle, 'Smart Shuffle', NaviGlyph.smartShuffle);
    await tester.pumpWidget(_app(Stack(children: [
      SmartBackdrop(context: ctx, songId: 'a'),
      const Center(child: SmartContextPill(context: ctx)),
    ])));
    expect(find.text('Playing from Smart Shuffle', findRichText: true), findsOneWidget);
    await tester.pumpWidget(_app(Stack(children: [
      SmartBackdrop(context: ctx, songId: 'b'),
      const Center(child: SmartContextPill(context: ctx)),
    ])));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Opacity), findsWidgets, reason: 'old and new backdrop overlap while they crossfade');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('GroundSurface paints the page colour and stays out of the way without one', (tester) async {
    DockGround.value.value = null;
    await tester.pumpWidget(_app(const GroundSurface(child: SizedBox(key: Key('x'), width: 10, height: 10))));
    expect(find.byType(ColoredBox).evaluate().where((e) => (e.widget as ColoredBox).color == const Color(0xFF123456)), isEmpty);
    DockGround.value.value = const Color(0xFF123456);
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == const Color(0xFF123456)), findsOneWidget);
    DockGround.value.value = null;
  });

  test('credit lists are shortened, short ones left alone', () {
    expect(shortArtists('Taylor Swift'), 'Taylor Swift');
    expect(shortArtists('A • B • C'), 'A • B • C');
    expect(shortArtists('A / B / C / D / E'), 'A • B • C +2');
    expect(shortArtists('HUNTR/X • EJAE • AUDREY NUNA • REI AMI • KPop Demon Hunters Cast'), 'HUNTR • X • EJAE +3');
  });
}

