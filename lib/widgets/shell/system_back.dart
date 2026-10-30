import 'package:flutter/material.dart';

import 'app_tab.dart';
import 'nav_stack.dart';

/// The system back button / gesture (and predictive back), the way a native
/// app treats it. The order, each step only when the one before has nothing to do:
///
///  1. an open sheet, dialog, menu or the player (routes above the app shell)
///     close first, because Flutter hands back to the topmost route;
///  2. then the current tab's stack goes up one page;
///  3. then a tab other than Home returns to Home;
///  4. then the app leaves.
///
/// [canPop] is only true at step 4, so the platform animates "leaving the app"
/// (predictive back) exactly when that is what will happen.
class SystemBackScope extends StatelessWidget {
  final AppTab tab;
  final VoidCallback onGoHome;
  final Widget child;
  const SystemBackScope({super.key, required this.tab, required this.onGoHome, required this.child});

  @override
  Widget build(BuildContext context) {
    final trail = tabTrails[tab]!;
    return AnimatedBuilder(
      animation: trail.routes,
      builder: (context, child) => PopScope(
        canPop: tab == AppTab.home && !trail.canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (!popActiveTab()) onGoHome();
        },
        child: child!,
      ),
      child: child,
    );
  }
}
