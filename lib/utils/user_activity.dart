import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// When the person last touched this device (a tap, a click, a key).
///
/// Taking playback from another of your devices must be something a person
/// asked for. Code that runs on its own (a restored queue, a remote state
/// arriving, a timer, an autoplay refill) has no touch behind it, so it asks
/// [UserActivity.recent] and stays out of the way when the answer is no.
class UserActivity {
  UserActivity._();

  static DateTime? _last;

  /// Starts listening for touches and keys. Call once at startup.
  static void install() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) mark();
    });
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent) mark();
      return false; // observe only
    });
  }

  /// Records an action that isn't a touch (a media button, a notification action).
  static void mark() => _last = DateTime.now();

  /// Whether the person did something in the last [within].
  static bool recent([Duration within = const Duration(seconds: 3)]) {
    final last = _last;
    return last != null && DateTime.now().difference(last) <= within;
  }

  /// For tests: pretend the person touched the screen just now (or never).
  static void debugSet(DateTime? at) => _last = at;
}
