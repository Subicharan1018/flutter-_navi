import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';
import 'package:navivibe/widgets/shell/tab_navigators.dart';
import 'package:navivibe/widgets/ui/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _themed(Widget child) => ThemeTokens(
      tokens: AppThemeTokens.fallback,
      child: MaterialApp(theme: AppTheme.build(AppThemeTokens.fallback), home: child),
    );

bool _fieldFocused(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  group('clear button', () {
    Future<TextEditingController> pumpField(WidgetTester tester) async {
      final controller = TextEditingController(text: 'abba');
      await tester.pumpWidget(_themed(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: NaviSearchField(controller: controller, voice: false),
        ),
      )));
      return controller;
    }

    Finder clear() => find.descendant(of: find.byType(CupertinoSearchTextField), matching: find.byType(CupertinoButton));

    testWidgets('is a full 44 pt touch target, and the field does not grow when it appears', (tester) async {
      final controller = await pumpField(tester);
      final size = tester.getSize(clear());
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      // Same field height with and without the button showing.
      final withText = tester.getSize(find.byType(CupertinoSearchTextField)).height;
      controller.clear();
      await tester.pump();
      expect(clear().hitTestable(), findsNothing);
      expect(tester.getSize(find.byType(CupertinoSearchTextField)).height, withText);
    });

    testWidgets('a tap near the edge of its square clears and keeps the keyboard', (tester) async {
      final controller = await pumpField(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(_fieldFocused(tester), isTrue);

      // Off the small glyph but inside the 44 pt square.
      final box = tester.getRect(clear());
      await tester.tapAt(box.topLeft + const Offset(4, 4));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(_fieldFocused(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });

  group('Search tab chosen again', () {
    final dir = Directory.systemTemp.createTempSync('search_field_test');
    setUpAll(() async {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
      SharedPreferences.setMockInitialValues({});
      await Hive.initFlutter('search_field_test');
      await HiveBoxes.init();
    });
    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    testWidgets('pops to Search and puts the caret in its field with the keyboard up', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _themed(const TabNavigators(tab: AppTab.search, visited: {AppTab.search})),
      ));
      await tester.pump();
      // Drilled into something from Search.
      tabNavigators[AppTab.search]!.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('album'))),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      reselectTab(AppTab.search);
      await tester.pumpAndSettle();

      expect(find.text('album'), findsNothing);
      expect(_fieldFocused(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(searchFieldRequest.value, isFalse, reason: 'the request is consumed');
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('other tabs only go back to their root', (tester) async {
      reselectTab(AppTab.home);
      expect(searchFieldRequest.value, isFalse);
    });
  });
}
