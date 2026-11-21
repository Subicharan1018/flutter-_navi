import 'package:flutter/foundation.dart';

// =============================================================================
// media_key_gate.dart — one media key press is handled once
//
// On Windows a hardware media key (keyboard, touchpad three-finger tap, volume
// flyout, Bluetooth headphones) reaches the app twice when the window is
// focused: as an SMTC button press and as an ordinary Flutter key event. Both
// are routed here so only the first one in a short window acts.
// =============================================================================

enum MediaKeyAction { play, pause, playPause, next, previous, stop }

class MediaKeyGate {
  MediaKeyGate({DateTime Function()? clock, this.window = const Duration(milliseconds: 350)})
      : _now = clock ?? DateTime.now;

  static final MediaKeyGate instance = MediaKeyGate();

  final DateTime Function() _now;
  final Duration window;

  /// True once the Windows SMTC session is up: it then owns the hardware
  /// media keys and the in-app key bindings step aside.
  bool smtcActive = false;

  DateTime? _lastAt;
  MediaKeyAction? _lastGroup;

  // Play, pause and toggle are one family: SMTC says "pause" where the focused
  // key event says "toggle", for the same physical press.
  static MediaKeyAction _group(MediaKeyAction a) =>
      (a == MediaKeyAction.play || a == MediaKeyAction.pause) ? MediaKeyAction.playPause : a;

  /// Runs [run] unless the same kind of press was handled a moment ago.
  /// Returns whether it ran.
  bool handle(MediaKeyAction action, VoidCallback run) {
    final now = _now();
    final group = _group(action);
    final last = _lastAt;
    if (last != null && _lastGroup == group && now.difference(last) < window) return false;
    _lastAt = now;
    _lastGroup = group;
    run();
    return true;
  }

  /// A focused-window key event: ignored while SMTC owns the keys.
  bool handleInApp(MediaKeyAction action, VoidCallback run) {
    if (smtcActive) return false;
    return handle(action, run);
  }
}
