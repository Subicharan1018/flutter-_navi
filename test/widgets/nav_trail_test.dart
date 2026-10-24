import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';

void main() {
  testWidgets('NavTrail follows a tab stack and names its crumbs', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final trail = NavTrail(AppTab.library);
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: key,
        observers: [trail],
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('root')),
      ),
    ));
    await tester.pump();
    expect(trail.canPop, isFalse);
    expect([for (final c in trail.crumbs) c.title], ['Library']);

    key.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Albums'),
      builder: (_) => const Text('albums'),
    ));
    await tester.pumpAndSettle();
    key.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Abbey Road'),
      builder: (_) => const Text('album'),
    ));
    await tester.pumpAndSettle();
    expect(trail.canPop, isTrue);
    expect([for (final c in trail.crumbs) c.title], ['Library', 'Albums', 'Abbey Road']);

    // A breadcrumb tap goes back to that step, dropping the ones after it.
    key.currentState!.popUntil((r) => r == trail.crumbs[1].route);
    await tester.pumpAndSettle();
    expect([for (final c in trail.crumbs) c.title], ['Library', 'Albums']);
    expect(find.text('albums'), findsOneWidget);
  });
}
