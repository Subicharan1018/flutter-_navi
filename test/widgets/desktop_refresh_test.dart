import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/ui/large_title_page.dart';

Widget _page(VoidCallback onRefresh) => MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: LargeTitlePage(
        title: 'Stats',
        onRefresh: () async => onRefresh(),
        slivers: const [SliverToBoxAdapter(child: SizedBox(height: 50))],
      ),
    );

void main() {
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  testWidgets('Windows: no pull-to-refresh; a Refresh button and F5 do it', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    var n = 0;
    await tester.pumpWidget(_page(() => n++));
    expect(find.byType(CupertinoSliverRefreshControl, skipOffstage: false), findsNothing);
    expect(find.byTooltip('Refresh (F5)'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh (F5)'));
    await tester.pump();
    expect(n, 1);
    // F5 works with focus anywhere on the page.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(n, 2);
  });

  testWidgets('phone: pull-to-refresh stays, no button', (tester) async {
    PlatformUtils.debugDesktopOverride = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page(() {}));
    expect(find.byType(CupertinoSliverRefreshControl, skipOffstage: false), findsOneWidget);
    expect(find.byTooltip('Refresh (F5)'), findsNothing);
  });
}
