import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs [action] once, [delay] after the last [schedule] call.
///
/// A window drag raises a resize or move event on every frame; saving on each
/// one means a platform round trip and a disk write 60 times a second. This
/// waits for the burst to end. [flush] runs a pending save at once (closing
/// the window must not wait for the timer). A failing save is reported and
/// forgotten: the next one still runs.
class TrailingSave {
  final Duration delay;
  final Future<void> Function() action;
  Timer? _timer;

  TrailingSave(this.delay, this.action);

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  /// Saves now if a save is pending; does nothing otherwise.
  void flush() {
    if (_timer == null) return;
    _timer!.cancel();
    _run();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _run() {
    _timer = null;
    action().catchError((Object e) => debugPrint('[TrailingSave] $e'));
  }
}
