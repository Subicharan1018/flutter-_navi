import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:window_manager/window_manager.dart';

/// Closing the window on Linux.
///
/// Letting GTK destroy the window crashed the app now and then (SIGSEGV): a
/// callback Flutter's GTK engine had queued on the main loop ran after the
/// view was gone. So the window is never torn down: the close is caught, what
/// must survive is saved, and the process ends.
class LinuxShutdown with WindowListener {
  LinuxShutdown(this.steps, {this.stepTimeout = const Duration(seconds: 3), @visibleForTesting void Function(int)? quit})
      : _quit = quit ?? exit;

  /// Run in order. One that fails or hangs does not stop the others.
  final List<Future<void> Function()> steps;
  final Duration stepTimeout;
  final void Function(int) _quit;
  bool _closing = false;

  Future<void> install() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() => unawaited(run());

  @visibleForTesting
  Future<void> run() async {
    if (_closing) return;
    _closing = true;
    for (final step in steps) {
      try {
        await step().timeout(stepTimeout);
      } catch (e) {
        debugPrint('[Shutdown] $e');
      }
    }
    _quit(0);
  }
}
