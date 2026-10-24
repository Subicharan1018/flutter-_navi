import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/ui/grouped_list.dart';

void main() {
  testWidgets('GroupedSwitchRow with icon and subtitle fits 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeTokens(
            tokens: AppThemeTokens.fallback,
            child: GroupedSection(
              header: 'Audio Quality',
              children: [
                GroupedSwitchRow(
                  title: 'Switch Automatically',
                  subtitle: 'Uses the Wi-Fi or cellular quality to match your connection.',
                  icon: NaviGlyph.swap,
                  value: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Switch Automatically'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
  });
}
