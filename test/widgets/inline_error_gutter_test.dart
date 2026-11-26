// A section's "didn't load" line starts where the section's heading does: the
// page margin, which is wider on desktop than on the phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/ui/states.dart';

void main() {
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  for (final (desktop, margin) in [(true, Space.xxl), (false, Space.gutter)]) {
    testWidgets('left edge, desktop: $desktop', (tester) async {
      PlatformUtils.debugDesktopOverride = desktop;
      await tester.pumpWidget(
        ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            home: Scaffold(
              body: InlineError(message: 'Charts didn’t load.', onRetry: () {}),
            ),
          ),
        ),
      );
      expect(tester.getTopLeft(find.text('Charts didn’t load.')).dx, margin);
    });
  }
}
