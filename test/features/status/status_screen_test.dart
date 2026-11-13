import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/status/logic/status_model.dart';
import 'package:navivibe/features/status/logic/status_providers.dart';
import 'package:navivibe/features/status/ui/status_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';

void main() {
  late Map<String, int> runs;
  String? copied;

  Future<void> pumpScreen(WidgetTester tester, {required bool desktop, Size size = const Size(420, 3000)}) async {
    PlatformUtils.debugDesktopOverride = desktop;
    addTearDown(() => PlatformUtils.debugDesktopOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    runs = {};
    copied = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Probe p(String id, ProbeResult r) => () async {
          runs[id] = (runs[id] ?? 0) + 1;
          return r;
        };
    await tester.pumpWidget(ProviderScope(
      overrides: [
        statusAppVersionProvider.overrideWith((ref) async => '1.2.3 (45)'),
        statusClockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1, 12)),
        statusProbesProvider.overrideWithValue({
          StatusIds.navidrome: p(StatusIds.navidrome, const ProbeResult(HealthLevel.ok, '42 ms · music.example.com')),
          StatusIds.shuffle: p(StatusIds.shuffle, const ProbeResult(HealthLevel.slow, '2.1 s')),
          StatusIds.fetcher: p(StatusIds.fetcher, const ProbeResult(HealthLevel.down, 'Can’t reach the server')),
          StatusIds.downloads: p(StatusIds.downloads, const ProbeResult(HealthLevel.ok, '0 queued · 0 running · 0 failed · idle')),
        }),
      ],
      child: MaterialApp(
        home: ThemeTokens(tokens: AppThemeTokens.fallback, child: const StatusScreen()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final desktop in [false, true]) {
    final name = desktop ? 'Windows layout' : 'phone layout';

    testWidgets('$name: states in words, checked time, version', (tester) async {
      await pumpScreen(tester, desktop: desktop, size: desktop ? const Size(1100, 900) : const Size(420, 3000));
      expect(find.text('Navidrome'), findsOneWidget);
      expect(find.text('OK'), findsWidgets);
      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('Down'), findsOneWidget);
      expect(find.textContaining('42 ms · music.example.com'), findsOneWidget);
      expect(find.textContaining('Checked just now'), findsWidgets);
      expect(find.text('1.2.3 (45)'), findsOneWidget);
      expect(find.text('Retry'), findsNWidgets(StatusIds.titles.length));
    });

    testWidgets('$name: Retry re-runs just that row', (tester) async {
      await pumpScreen(tester, desktop: desktop, size: desktop ? const Size(1100, 900) : const Size(420, 3000));
      expect(runs[StatusIds.fetcher], 1);
      await tester.tap(find.byKey(const ValueKey('retry-fetcher')));
      await tester.pumpAndSettle();
      expect(runs[StatusIds.fetcher], 2);
      expect(runs[StatusIds.navidrome], 1);
    });

    testWidgets('$name: Copy diagnostics puts a redacted report on the clipboard', (tester) async {
      await pumpScreen(tester, desktop: desktop, size: desktop ? const Size(1100, 1000) : const Size(420, 3000));
      await tester.ensureVisible(find.byKey(const ValueKey('copy-diagnostics')));
      await tester.tap(find.byKey(const ValueKey('copy-diagnostics')));
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect(copied, contains('NaviVibe diagnostics'));
      expect(copied, contains('App: 1.2.3 (45)'));
      expect(copied, contains('Online fetch: Down'));
      expect(copied, isNot(contains('assword')));
    });
  }
}
