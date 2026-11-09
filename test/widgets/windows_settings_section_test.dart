import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/services/global_hotkey.dart';
import 'package:navivibe/services/windows_startup.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/windows_settings_section.dart';

class _Driver implements HotkeyDriver {
  final registered = <HotkeyBinding>[];
  @override
  Future<void> register(HotkeyBinding b, VoidCallback onPressed) async => registered.add(b);
  @override
  Future<void> unregisterAll() async => registered.clear();
}

void main() {
  final onWindows = Platform.isWindows;
  late Directory dir;
  late List<List<String>> reg;
  late _Driver driver;
  late GlobalHotkey hotkey;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_win_settings');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
  });
  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() async {
    await HiveBoxes.prefs.clear();
    PlatformUtils.debugDesktopOverride = true;
    reg = [];
    driver = _Driver();
    hotkey = GlobalHotkey(driver: driver);
    await hotkey.init(() {});
  });

  Widget app() => MaterialApp(
        theme: AppTheme.build(AppThemeTokens.fallback),
        builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WindowsSettingsSection(
              startup: WindowsStartup(
                executable: r'C:\NaviVibe.exe',
                run: (a) async {
                  reg.add(a);
                  // Nothing registered yet: a query fails, add/delete succeed.
                  return ProcessResult(0, a.first == 'query' ? 1 : 0, '', '');
                },
              ),
              hotkey: hotkey,
            ),
          ),
        ),
      );

  testWidgets('lists start with Windows and the shortcut, which shows its default', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Start with Windows'), findsOneWidget);
    expect(find.text('Global shortcut'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Space'), findsOneWidget);
  }, skip: !onWindows);

  testWidgets('turning Start with Windows on writes the Run entry', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Start with Windows'));
    await tester.pump();
    await tester.pump();
    expect(reg.any((a) => a.first == 'add' && a.last == '/f'), isTrue);
    expect(reg.any((a) => a.first == 'add' && a.any((s) => s.endsWith('--minimized'))), isTrue);
  }, skip: !onWindows);

  testWidgets('the shortcut row records a new combination and registers it', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('Ctrl+Alt+Space'));
    await tester.pump();
    expect(find.text('Press keys, Esc to cancel'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('Ctrl+Shift+M'), findsOneWidget);
    expect(driver.registered.single.label, 'Ctrl+Shift+M');
  }, skip: !onWindows);
}
