import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../utils/platform_utils.dart';

// =============================================================================
// The phone dock as one sheet of frosted glass.
//
// The Jam pill, the mini player and the tab bar share ONE blur layer ([GlassDock])
// instead of three; the capsules inside only tint. Content scrolls visibly under
// it, so every tab page pads its end by the dock's measured height
// ([DockInsetScope] / [dockClearance]).
//
// Glass costs GPU time, so it falls back to the solid band the app used before
// when: motion is Reduced (Settings or system), the system asks for high
// contrast, the device is a TV, or frames are measurably too slow with it on
// ([GlassGovernor]).
// =============================================================================

/// The dock's current height (including the bottom safe area), measured.
abstract final class DockInset {
  static final ValueNotifier<double> height = ValueNotifier(0);
}

/// Bottom padding a scrolling page needs so its last row can rise above the
/// dock. Inside the tab shell [MediaQuery] already carries the dock (see
/// [DockInsetScope]); elsewhere it is just the safe area.
double dockClearance(BuildContext context) => MediaQuery.paddingOf(context).bottom + Space.lg;

/// Adds the dock's height to the bottom padding of everything beneath it.
class DockInsetScope extends StatelessWidget {
  final Widget child;
  const DockInsetScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: DockInset.height,
      child: child,
      builder: (context, dock, child) {
        final mq = MediaQuery.of(context);
        if (dock <= mq.padding.bottom) return child!;
        return MediaQuery(data: mq.copyWith(padding: mq.padding.copyWith(bottom: dock)), child: child!);
      },
    );
  }
}

/// Watches raster time while the glass is on and turns it off for the session
/// when it sustainably misses the frame budget: the device can't afford it.
class GlassGovernor {
  GlassGovernor._();

  /// True once glass has been judged too slow.
  static final ValueNotifier<bool> tooSlow = ValueNotifier(false);

  /// Frames per verdict, the per-frame budget, and the share of over-budget
  /// frames that counts as "sustained".
  static const int window = 120;
  static const Duration budget = Duration(milliseconds: 24);
  static const double share = 0.5;

  static int _seen = 0;
  static int _over = 0;
  static bool _attached = false;

  /// Feeds one frame's raster time. Returns true when this frame tips the
  /// verdict to "too slow".
  @visibleForTesting
  static bool report(Duration raster) {
    if (tooSlow.value) return false;
    _seen++;
    if (raster > budget) _over++;
    if (_seen < window) return false;
    final slow = _over / _seen >= share;
    _seen = 0;
    _over = 0;
    if (slow) tooSlow.value = true;
    return slow;
  }

  @visibleForTesting
  static void reset() {
    tooSlow.value = false;
    _seen = 0;
    _over = 0;
  }

  /// Starts listening (release builds only: debug frames are always slow).
  static void attach() {
    if (_attached || !kReleaseMode) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        report(t.rasterDuration);
      }
    });
  }
}

/// Whether the dock may use glass on this device and under these settings.
bool dockGlassAllowed(BuildContext context) =>
    !PlatformUtils.isTv &&
    context.motionFull &&
    !MediaQuery.highContrastOf(context) &&
    !GlassGovernor.tooSlow.value;

/// Tells the capsules in the dock whether they sit on glass.
class DockGlass extends InheritedWidget {
  final bool on;
  const DockGlass({super.key, required this.on, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DockGlass>()?.on ?? false;

  @override
  bool updateShouldNotify(DockGlass old) => old.on != on;
}

/// A dock capsule's fill: [solid] on the solid band, the same hue part-clear on
/// glass so the blurred page shows through.
Color dockCapsuleFill(BuildContext context, Color solid) =>
    DockGlass.of(context) ? solid.withValues(alpha: 0.72) : solid;

/// A dock capsule's hairline: a light edge on glass, a lifted step otherwise.
Color dockCapsuleEdge(BuildContext context, Color solid, {double lift = 0.12}) =>
    DockGlass.of(context) ? const Color(0x2BFFFFFF) : Color.lerp(solid, Colors.white, lift)!;

/// The dock's surface: a blurred, tinted sheet with a hairline and a soft top
/// highlight when [glass] is allowed, the solid [ground] band otherwise. Also
/// publishes the dock's height to [DockInset].
class GlassDock extends StatefulWidget {
  final Color ground;
  final Widget child;
  const GlassDock({super.key, required this.ground, required this.child});

  /// Blur strength and the sheet's top corner radius.
  static const double sigma = 24;
  static const double radius = 26;

  /// Tint over the blur: enough ground colour that text stays legible on any
  /// page, little enough that the page reads through.
  static const double tintAlpha = 0.6;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    GlassGovernor.attach();
  }

  void _measure() {
    final h = _key.currentContext?.size?.height;
    if (h != null && h != DockInset.height.value) DockInset.height.value = h;
  }

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) => mounted ? _measure() : null);
    return ValueListenableBuilder<bool>(
      valueListenable: GlassGovernor.tooSlow,
      builder: (context, _, _) {
        final glass = dockGlassAllowed(context);
        final body = NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            SchedulerBinding.instance.addPostFrameCallback((_) => mounted ? _measure() : null);
            return false;
          },
          child: SizeChangedLayoutNotifier(
            child: Padding(padding: const EdgeInsets.only(top: Space.sm), child: widget.child),
          ),
        );
        return DockGlass(
          on: glass,
          child: RepaintBoundary(
            key: _key,
            child: glass ? _frosted(body) : AnimatedContainer(duration: Motion.standard, color: widget.ground, child: body),
          ),
        );
      },
    );
  }

  Widget _frosted(Widget body) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(GlassDock.radius)),
      side: BorderSide(color: Color(0x24FFFFFF), width: 0.5),
    );
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: GlassDock.sigma, sigmaY: GlassDock.sigma, tileMode: TileMode.clamp),
        child: AnimatedContainer(
          duration: Motion.standard,
          decoration: ShapeDecoration(
            shape: shape,
            color: widget.ground.withValues(alpha: GlassDock.tintAlpha),
          ),
          foregroundDecoration: const ShapeDecoration(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.22],
              colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}
