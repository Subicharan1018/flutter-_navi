import 'package:flutter/widgets.dart';

/// Where the pointer last went down, so a desktop context menu can open at the
/// cursor instead of in the middle of the window. Wrap the app once
/// ([PointerAnchor]); read [PointerAnchor.recent] when opening a menu.
class PointerAnchor extends StatelessWidget {
  final Widget child;
  const PointerAnchor({super.key, required this.child});

  static Offset? _position;
  static DateTime? _at;

  /// Test seam and keyboard-triggered menus: pretend the pointer went down here.
  static void record(Offset position) {
    _position = position;
    _at = DateTime.now();
  }

  static void reset() {
    _position = null;
    _at = null;
  }

  /// The last pointer-down position if it happened in the last [within], else null
  /// (the menu was opened from the keyboard, so there is no cursor to anchor to).
  static Offset? recent({Duration within = const Duration(seconds: 2)}) {
    final at = _at;
    if (at == null || DateTime.now().difference(at) > within) return null;
    return _position;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => record(e.position),
        child: child,
      );
}
