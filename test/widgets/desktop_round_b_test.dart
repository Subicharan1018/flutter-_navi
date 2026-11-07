import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
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
