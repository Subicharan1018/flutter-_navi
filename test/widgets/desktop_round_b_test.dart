import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/screens/home_screen.dart' show continueTileTint;
import 'package:navivibe/widgets/shell/shortcuts_help.dart' show KeyboardHelpButton;
import 'package:navivibe/widgets/ui/grouped_list.dart' show GroupedSwitchRow;
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/shell/desktop/library_rail.dart';
import 'package:navivibe/widgets/ui/media.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    );

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);

  group('collapsed rail', () {
    testWidgets('an icon-only row names itself in a tooltip and marks the active one', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 64,
        child: Column(children: [
          RailRow(icon: NaviGlyph.home, label: 'Home', iconOnly: true, selected: true, onTap: () {}),
          RailRow(icon: NaviGlyph.library, label: 'Library', iconOnly: true, onTap: () {}),
        ]),
      )));
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Library'), findsOneWidget);
      // The active marker: a 3 px bar, on the selected row only.
      final bars = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 3);
      expect(bars, findsOneWidget);
    });
  });

  group('Play says what it plays', () {
    testWidgets('the scope line shows next to the buttons on desktop', (tester) async {
      await tester.pumpWidget(_host(PlayShuffleButtons(onPlay: () {}, onShuffle: () {}, scope: 'Plays your whole library, from the top')));
      expect(find.text('Plays your whole library, from the top'), findsOneWidget);
    });

    testWidgets('without a scope nothing extra is drawn', (tester) async {
      await tester.pumpWidget(_host(PlayShuffleButtons(onPlay: () {}, onShuffle: () {})));
      expect(find.textContaining('Plays'), findsNothing);
    });
  });

  group('last polish', () {
    testWidgets('the desktop toggle is a labelled button at least 28 px tall and says its state', (tester) async {
      final handle = tester.ensureSemantics();
      var on = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (c, set) => GroupedSwitchRow(title: 'Allow HTTP', value: on, onChanged: (v) => set(() => on = v)),
      )));
      final node = tester.getSemantics(find.bySemanticsLabel('Allow HTTP').last);
      expect(node.flagsCollection.isToggled.toString(), isNot(contains('none')), reason: 'it announces on/off');
      expect(node.flagsCollection.isButton, isTrue);
      expect(tester.getSize(find.byType(NaviPressable)).height, greaterThanOrEqualTo(28));
      await tester.tap(find.byType(NaviPressable));
      expect(on, isTrue);
      handle.dispose();
    });

    testWidgets('a bright cover cannot make a Continue tile unreadable', (tester) async {
      // 4.5:1 against white text, whatever the tint.
      final c = continueTileTint(const Color(0xFF1C1C1E), const Color(0xFFFFFF00), 0.30, Colors.white);
      final l = c.computeLuminance();
      expect((1.05) / (l + 0.05), greaterThanOrEqualTo(4.5));
    });

    testWidgets('Library tiles and shelf tiles come from one scale', (tester) async {
      final (cols, size) = desktopTiles(1318, 170, 16);
      expect(cols, 7);
      expect(size, inInclusiveRange(165, 190));
    });

    testWidgets('the shortcuts button is a keyboard glyph, not a bare question mark', (tester) async {
      await tester.pumpWidget(_host(const KeyboardHelpButton()));
      expect(find.bySemanticsLabel('Keyboard shortcuts'), findsOneWidget);
    });
  });

  group('short shelf', () {
    testWidgets('a shelf with few items ends in a See all tile that opens the list', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 800);
      addTearDown(tester.view.reset);
      var opened = 0;
      await tester.pumpWidget(_host(SizedBox(
        width: 1600,
        child: MediaShelf(
          title: 'Your Playlists',
          onSeeAll: () => opened++,
          itemCount: 3,
          cardSize: 176,
          itemBuilder: (c, i) => SizedBox(key: ValueKey('card$i')),
        ),
      )));
      expect(find.text('See all'), findsOneWidget);
      await tester.tap(find.text('See all'));
      expect(opened, 1);
    });

    testWidgets('a full shelf has no See all tile', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(SizedBox(
        width: 1600,
        child: MediaShelf(
          title: 'Recently Played',
          onSeeAll: () {},
          itemCount: 12,
          cardSize: 176,
          itemBuilder: (c, i) => SizedBox(key: ValueKey('card$i')),
        ),
      )));
      expect(find.text('See all'), findsNothing);
    });
  });
}
