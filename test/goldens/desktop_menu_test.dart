// The Windows context menu and hover state, rendered for real.
//
//   flutter test test/goldens/desktop_menu_test.dart --update-goldens

@Tags(['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/desktop_dialogs.dart';
import 'package:navivibe/widgets/ui/action_sheet.dart';

import 'golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
  });

  testWidgets('right-click menu at the cursor, 1100x700', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 700);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(PointerAnchor(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(40),
              child: Row(children: [
                for (final n in ['Play', 'Shuffle', 'Add'])
                  Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: CupertinoClickable(
                      onTap: () {},
                      semanticLabel: n,
                      focusRadius: 20,
                      child: Container(
                        width: 160,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white12,
                        ),
                        child: Text(n),
                      ),
                    ),
                  ),
              ]),
            ),
          );
        }),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(260, 60));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(260, 60)); // hovering "Shuffle"
    await tester.pump();

    PointerAnchor.record(const Offset(420, 120));
    showPlatformSheet<void>(
      context: ctx,
      menu: true,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHeader(title: 'Song', subtitle: 'Artist'),
        SheetGroup(children: [
          SheetAction(label: 'Play Next', icon: NaviGlyph.playNext, onTap: () {}),
          SheetAction(label: 'Add to Queue', icon: NaviGlyph.queue, onTap: () {}),
          SheetAction(label: 'Add to a Playlist…', icon: NaviGlyph.addToPlaylist, onTap: () {}),
        ]),
        SheetGroup(children: [
          SheetAction(label: 'Favorite', icon: NaviGlyph.star, onTap: () {}),
          SheetAction(label: 'Download', icon: NaviGlyph.download, onTap: () {}),
          SheetAction(label: 'Remove from Playlist', icon: NaviGlyph.minus, destructive: true, onTap: () {}),
        ]),
      ]),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('desktop/menu.png'));
  });
}
