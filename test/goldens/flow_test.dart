/// Home's Flow on a phone (390 wide @3x) and on Windows (1280 wide): idle with a
/// mood picked, running with the blend strip, and failed with Retry.
///
///   flutter test test/goldens/flow_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/flow/logic/flow_controller.dart';
import 'package:navivibe/features/flow/ui/flow_section.dart';
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/utils/platform_utils.dart';

import '../features/flow/flow_section_test.dart' show flowApp;
import 'golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  const idle = FlowState(mood: 'chill');
  const running = FlowState(active: true, mood: 'chill', blend: FlowBlend(familiar: 6, fresh: 3, explore: 1));
  const failed = FlowState(error: 'Flow couldn’t load songs. Try again.');

  Future<void> shoot(WidgetTester tester, FlowState state, String file, {required bool desktop}) async {
    PlatformUtils.debugDesktopOverride = desktop;
    tester.view.physicalSize = desktop ? const Size(1280, 300) : const Size(390 * 3, 420 * 3);
    tester.view.devicePixelRatio = desktop ? 1 : 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(flowApp(const FlowSection(), state, []));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('flow/$file.png'));
  }

  for (final (name, state) in [('idle', idle), ('running', running), ('failed', failed)]) {
    testWidgets('phone $name', (tester) => shoot(tester, state, 'phone_$name', desktop: false));
    testWidgets('windows $name', (tester) => shoot(tester, state, 'windows_$name', desktop: true));
  }
}
