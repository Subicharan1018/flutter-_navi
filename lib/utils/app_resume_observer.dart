import 'package:flutter/widgets.dart';

/// Calls [onResume] each time the app comes back to the foreground.
class AppResumeObserver with WidgetsBindingObserver {
  AppResumeObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
