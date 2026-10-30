import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';
import 'package:navivibe/widgets/shell/system_back.dart';

/// The system back button / gesture, simulated with `handlePopRoute` (what
/// Android's back and predictive back deliver to Flutter).
void main() {
  late AppTab shown;
  late StateSetter rebuild;

  Widget app() => MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return SystemBackScope(
            tab: shown,
            onGoHome: () => setState(() {
              shown = AppTab.home;
              activeTab.value = AppTab.home;
            }),
            child: Scaffold(
              body: Stack(children: [
                for (final t in [AppTab.home, AppTab.library])
                  Offstage(
                    offstage: t != shown,
                    child: Navigator(
                      key: tabNavigators[t],
                      observers: [tabTrails[t]!],
                      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Text('${t.name} root')),
                    ),
                  ),
              ]),
            ),
          );
        }),
      );

  setUp(() {
    shown = AppTab.library;
    activeTab.value = AppTab.library;
  });

  testWidgets('back closes a dialog, then pops the stack, then goes Home, then leaves', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    // Library → Albums page → a dialog on top.
    tabNavigators[AppTab.library]!.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Albums'),
      builder: (_) => const Text('albums page'),
    ));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('albums page'));
    showDialog<void>(context: context, useRootNavigator: true, builder: (_) => const AlertDialog(title: Text('a dialog')));
    await tester.pumpAndSettle();
    expect(find.text('a dialog'), findsOneWidget);

    // 1. the dialog goes first
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('a dialog'), findsNothing);
    expect(find.text('albums page'), findsOneWidget, reason: 'the page under the dialog is untouched');

    // 2. then the tab's stack goes up a page
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('albums page'), findsNothing);
    expect(shown, AppTab.library, reason: 'still on Library, at its root');

    // 3. then a non-Home tab returns to Home
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(shown, AppTab.home);

    // 4. only then the app leaves (the platform handles it: handlePopRoute reports "not handled")
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('canPop is true only when back would leave the app (predictive back needs this)', (tester) async {
    shown = AppTab.home;
    activeTab.value = AppTab.home;
    await tester.pumpWidget(app());
    await tester.pump();
    PopScope scope() => tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
    expect(scope().canPop, isTrue, reason: 'Home at its root: back leaves the app');

    tabNavigators[AppTab.home]!.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Playlist'),
      builder: (_) => const Text('playlist'),
    ));
    await tester.pumpAndSettle();
    expect(scope().canPop, isFalse, reason: 'a pushed page: back goes up first');

    rebuild(() => shown = AppTab.library);
    await tester.pump();
    expect(scope().canPop, isFalse, reason: 'another tab: back returns to Home first');
  });
}
