import 'package:flutter/material.dart';

import 'app_tab.dart';
import 'nav_stack.dart';

/// The tabs' content: one Navigator per visited tab, stacked, only the
/// current one showing. Switching tabs never loses a tab's history or scroll
/// position, in any shell.
class TabNavigators extends StatelessWidget {
  final AppTab tab;

  /// Tabs built so far; a tab is built the first time it's opened.
  final Set<AppTab> visited;

  const TabNavigators({super.key, required this.tab, required this.visited});

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: tab.index,
      children: [
        for (final destination in AppTab.values)
          visited.contains(destination)
              // Hidden tabs stop animating, can't claim the dock colour and
              // can't take focus from the visible one.
              ? TickerMode(
                  enabled: destination == tab,
                  child: ExcludeFocus(
                    excluding: destination != tab,
                    child: Navigator(
                      key: tabNavigators[destination],
                      observers: [tabTrails[destination]!],
                      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => destination.screen),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
      ],
    );
  }
}
