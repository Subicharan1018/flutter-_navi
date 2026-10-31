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

/// A surface in the current page's own colour, optionally [darken]ed or
/// [lift]ed a little, so chrome around a tinted page (top bar, side panel, rail)
/// is one continuous surface with it instead of a black frame. Without a tint
/// it paints nothing and the surrounding default shows.
class GroundSurface extends StatelessWidget {
  final double darken;
  final double lift;
  final Widget child;
  const GroundSurface({super.key, this.darken = 0, this.lift = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, ground, child) {
        if (ground == null) return child!;
        var c = ground;
        if (darken > 0) c = Color.lerp(c, const Color(0xFF000000), darken)!;
        if (lift > 0) c = Color.lerp(c, const Color(0xFFFFFFFF), lift)!;
        return ColoredBox(color: c, child: child);
      },
      child: child,
    );
  }
}

enum PaneSide { leading, trailing }

/// A side pane (sidebar on the left, Now Playing panel on the right) that grows
/// out of the page's own tint: at the seam it is exactly the page's colour and
/// it deepens toward the window edge, so the album-coloured page flows into
/// both sides with no hard edge. Without a tint it is the flat [fallback].
class GroundPane extends StatelessWidget {
  final PaneSide side;
  final Color fallback;
  final double darken;
  final Widget child;
  const GroundPane({
    super.key,
    required this.side,
    required this.fallback,
    this.darken = 0.55,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, ground, child) {
        if (ground == null) return ColoredBox(color: fallback, child: child);
        final edge = Color.lerp(ground, const Color(0xFF000000), darken)!;
        final leading = side == PaneSide.leading;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: leading ? [edge, ground] : [ground, edge],
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// The hairline between a pane and the page, only while there is no tint to
/// blend: a tinted page flows into its panes instead.
class GroundDivider extends StatelessWidget {
  final Color color;
  const GroundDivider({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, ground, _) =>
          ground == null ? Container(width: 0.5, color: color) : const SizedBox(width: 0),
    );
  }
}
