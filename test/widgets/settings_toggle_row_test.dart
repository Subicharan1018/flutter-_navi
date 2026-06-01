import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/core/theme.dart';

void main() {
  testWidgets('SettingsToggleRow with subtitle fits 320px width without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeTokens(
            tokens: ThemeVariants.spotify(),
            child: Builder(builder: (context) {
              return SettingsToggleRow(
                title: 'Auto quality switch',
                subtitle: 'Automatically selects Wi-Fi or mobile bitrate by connection',
                value: false,
                onChanged: (_) {},
              );
            }),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Auto quality switch'), findsOneWidget);
    expect(find.text('Automatically selects Wi-Fi or mobile bitrate by connection'), findsOneWidget);
  });
}
