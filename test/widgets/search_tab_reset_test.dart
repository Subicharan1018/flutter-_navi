import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';

void main() {
  testWidgets('leaving Search and coming back starts from its first page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: tabNavigators[AppTab.search],
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('search root')),
      ),
    ));
    tabNavigators[AppTab.search]!.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('an album I opened')));
    await tester.pumpAndSettle();
    expect(find.text('an album I opened'), findsOneWidget);

    resetSearchTab();
    await tester.pumpAndSettle();
    expect(find.text('search root'), findsOneWidget);
    expect(find.text('an album I opened'), findsNothing);
  });
}
