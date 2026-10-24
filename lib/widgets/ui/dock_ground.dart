import 'package:flutter/widgets.dart';

/// The colour of the page currently on screen, so the floating dock (mini
/// player + tab bar) can sit on a solid band of that same colour instead of
/// a black fade smeared over an artwork-coloured page.
abstract final class DockGround {
  /// Null means the app's default ground.
  static final ValueNotifier<Color?> value = ValueNotifier(null);
}

/// Publishes [color] as the dock ground while this page is the visible,
/// topmost route of the active tab. Pages that keep the default ground pass
/// null. Inactive tabs are wrapped in a disabled [TickerMode] by the shell,
/// so a rebuild in a hidden tab never steals the dock.
class DockGroundScope extends StatelessWidget {
  final Color? color;
  final Widget child;
  const DockGroundScope({super.key, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    final visible = (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.valuesOf(context).enabled;
    if (visible && DockGround.value.value != color) {
      // Publish after this frame: the shell listens and rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) => DockGround.value.value = color);
    }
    return child;
  }
}
