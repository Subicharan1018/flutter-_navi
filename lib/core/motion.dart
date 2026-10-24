import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

// =============================================================================
// Motion helpers.
//
// Durations and curves live in [Motion] (theme.dart). This file is the one
// place that decides *whether* to move ([MotionScope], from Settings ▸ Motion
// and the system's "remove animations") and holds the reusable effects:
// staggered [Entrance], [PressScale], [Pulse], [Shimmer], [Drift] and the
// [NaviPageTransitionsBuilder]. Every effect is a no-op when motion is
// Reduced, and none of them rebuilds anything but its own small subtree.
// =============================================================================

/// Settings ▸ Motion.
enum MotionLevel {
  full,
  reduced;

  String get label => switch (this) { full => 'Full', reduced => 'Reduced' };

  String get summary => switch (this) {
        full => 'Covers drift, lists glide in and hearts burst.',
        reduced => 'Only the motion that explains what changed. Saves battery.',
      };
}

/// Tells the tree whether decorative motion is allowed: Settings says Full and
/// the system hasn't asked for animations to be removed.
class MotionScope extends InheritedWidget {
  final bool full;
  const MotionScope({super.key, required this.full, required super.child});

  /// Resolves [level] against the system setting.
  factory MotionScope.resolve({
    Key? key,
    required MotionLevel level,
    required bool systemReduced,
    required Widget child,
  }) =>
      MotionScope(key: key, full: level == MotionLevel.full && !systemReduced, child: child);

  @override
  bool updateShouldNotify(MotionScope old) => old.full != full;
}

extension MotionContext on BuildContext {
  /// Whether decorative motion is allowed. Subscribes: use inside `build`.
  /// Without a [MotionScope] (tests, isolated widgets) the system setting rules.
  bool get motionFull {
    final scope = dependOnInheritedWidgetOfExactType<MotionScope>();
    if (scope != null) return scope.full;
    return !(MediaQuery.maybeDisableAnimationsOf(this) ?? false);
  }

  /// Same answer without subscribing: for `initState` and event callbacks.
  bool get motionFullNow {
    final scope = getInheritedWidgetOfExactType<MotionScope>();
    if (scope != null) return scope.full;
    return !(getInheritedWidgetOfExactType<MediaQuery>()?.data.disableAnimations ?? false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entrance — fade + rise, staggered, first appearance only
// ─────────────────────────────────────────────────────────────────────────────

/// Remembers which lists have already played their entrance this session.
@visibleForTesting
final Set<String> seenEntrances = <String>{};

/// Fades and lifts its child in, [index] steps behind the first row. Plays only
/// the first time a [group] shows (the rows built in its first frame); rows
/// built later by scrolling, and every later visit, appear at rest. Only the
/// first [maxStagger] rows are delayed, so a long list never waits.
class Entrance extends StatefulWidget {
  final String group;
  final int index;
  final Widget child;
  final double rise;

  const Entrance({super.key, required this.group, required this.child, this.index = 0, this.rise = 14});

  static const int maxStagger = 8;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _t = kAlwaysCompleteAnimation;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final first = !seenEntrances.contains(widget.group);
    if (first) {
      // Everything built this frame is "first"; later rows see the mark.
      SchedulerBinding.instance.addPostFrameCallback((_) => seenEntrances.add(widget.group));
    }
    if (!first || !context.motionFull) return;
    final step = widget.index.clamp(0, Entrance.maxStagger);
    final total = Motion.slow + Motion.stagger * step;
    final c = _c = AnimationController(vsync: this, duration: total)..forward();
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(Motion.stagger.inMicroseconds * step / total.inMicroseconds, 1, curve: Motion.decelerate),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same tree shape at rest and in flight, so the child keeps its state.
    return FadeTransition(
      opacity: _t,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Transform.translate(offset: Offset(0, widget.rise * (1 - _t.value)), child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Press feedback
// ─────────────────────────────────────────────────────────────────────────────

/// The scale a pressed control settles at: 1 when motion is reduced.
double pressedScale(BuildContext context, double scale) => context.motionFull ? scale : 1.0;

/// Dips its child while a pointer is down on it. Listens without joining the
/// gesture arena, so the child's own taps and drags work untouched.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const PressScale({super.key, required this.child, this.scale = 0.96});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.press,
    reverseDuration: Motion.standard,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 1, end: pressedScale(context, widget.scale)).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Motion.spring),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _c.forward(),
      onPointerUp: (_) => _c.reverse(),
      onPointerCancel: (_) => _c.reverse(),
      child: ScaleTransition(scale: scale, child: widget.child),
    );
  }
}

/// A one-off pop: scales its child up and back each time [trigger] changes
/// (e.g. a checkmark landing, a playlist receiving a song).
class Pulse extends StatefulWidget {
  final Object? trigger;
  final double peak;
  final Widget child;
  const Pulse({super.key, required this.trigger, required this.child, this.peak = 1.18});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slow);

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && context.motionFullNow) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: widget.peak).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
        TweenSequenceItem(tween: Tween(begin: widget.peak, end: 1.0).chain(CurveTween(curve: Motion.spring)), weight: 65),
      ]).animate(_c),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer — one sweep over a whole skeleton, not one per box
// ─────────────────────────────────────────────────────────────────────────────

/// Sweeps a soft highlight across [child] (a skeleton made of plain filled
/// boxes). One shader for the whole group; it stops under Reduced motion and
/// whenever its route is off screen (the ticker is muted).
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.motionFull) {
      _c.stop();
      return widget.child;
    }
    if (!_c.isAnimating) _c.repeat();
    final glow = ThemeTokens.of(context).textPrimary.withValues(alpha: 0.10);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) {
            final x = -1.0 + 3.0 * _c.value;
            return LinearGradient(
              begin: Alignment(x - 0.6, 0),
              end: Alignment(x + 0.6, 0),
              colors: [const Color(0x00000000), glow, const Color(0x00000000)],
            ).createShader(r);
          },
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drift — slow idle motion on generated covers
// ─────────────────────────────────────────────────────────────────────────────

/// Slowly pans a slightly enlarged [child] inside its own clip, so a generated
/// cover feels alive. The child is rasterised once; only a layer transform
/// changes per frame. Stops under Reduced motion and when its route is hidden.
class Drift extends StatefulWidget {
  final Widget child;
  final double radius;
  const Drift({super.key, required this.child, this.radius = 0});

  /// Enlargement that leaves room to pan without showing an edge.
  static const double zoom = 1.12;

  @override
  State<Drift> createState() => _DriftState();
}

class _DriftState extends State<Drift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 16));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.radius > 0 ? BorderRadius.circular(widget.radius) : BorderRadius.zero;
    if (!context.motionFull) {
      _c.stop();
      return ClipRRect(borderRadius: clip, child: widget.child);
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
    final ease = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return ClipRRect(
      borderRadius: clip,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: ease,
          child: widget.child,
          builder: (context, child) {
            final s = (Drift.zoom - 1) / 2; // max pan as a fraction of size
            return FractionalTranslation(
              translation: Offset((ease.value - 0.5) * 2 * s * 0.8, (0.5 - ease.value) * 2 * s * 0.5),
              child: Transform.scale(scale: Drift.zoom, child: child),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Play / pause morph
// ─────────────────────────────────────────────────────────────────────────────

/// The play triangle and the pause bars as the same two quads, so one turns
/// into the other instead of swapping. Snaps when motion is Reduced.
class PlayPauseMorph extends StatefulWidget {
  final bool playing;
  final double size;
  final Color color;
  const PlayPauseMorph({super.key, required this.playing, required this.size, required this.color});

  @override
  State<PlayPauseMorph> createState() => _PlayPauseMorphState();
}

class _PlayPauseMorphState extends State<PlayPauseMorph> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.standard,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseMorph old) {
    super.didUpdateWidget(old);
    if (old.playing == widget.playing) return;
    final target = widget.playing ? 1.0 : 0.0;
    if (context.motionFullNow) {
      _c.animateTo(target, curve: Motion.ease);
    } else {
      _c.value = target;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: PlayPausePainter(_c, widget.color),
      ),
    );
  }
}

/// Paints the morph at [progress] (0 = play, 1 = pause).
class PlayPausePainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;
  PlayPausePainter(this.progress, this.color) : super(repaint: progress);

  // Each shape is two quads, four points each, in a unit square.
  static const _play = <Offset>[
    Offset(0.28, 0.16), Offset(0.52, 0.31), Offset(0.52, 0.69), Offset(0.28, 0.84), //
    Offset(0.52, 0.31), Offset(0.82, 0.5), Offset(0.82, 0.5), Offset(0.52, 0.69),
  ];
  static const _pause = <Offset>[
    Offset(0.24, 0.16), Offset(0.42, 0.16), Offset(0.42, 0.84), Offset(0.24, 0.84), //
    Offset(0.58, 0.16), Offset(0.76, 0.16), Offset(0.76, 0.84), Offset(0.58, 0.84),
  ];

  /// The outline points at [t]; exposed for tests.
  static List<Offset> pointsAt(double t) => [for (var i = 0; i < 8; i++) Offset.lerp(_play[i], _pause[i], t)!];

  @override
  void paint(Canvas canvas, Size size) {
    final pts = pointsAt(progress.value.clamp(0.0, 1.0));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final round = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.06;
    for (var q = 0; q < 2; q++) {
      final path = Path()..moveTo(pts[q * 4].dx * size.width, pts[q * 4].dy * size.height);
      for (var i = 1; i < 4; i++) {
        path.lineTo(pts[q * 4 + i].dx * size.width, pts[q * 4 + i].dy * size.height);
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, round);
    }
  }

  @override
  bool shouldRepaint(PlayPausePainter old) => old.color != color || old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page transitions
// ─────────────────────────────────────────────────────────────────────────────

/// Apple's push (slide in, previous page parallaxes back, swipe from the left
/// edge to return) on phones; a gentle fade-forward on desktop; a plain
/// cross-fade when motion is Reduced. Every route that uses the theme gets it.
class NaviPageTransitionsBuilder extends PageTransitionsBuilder {
  const NaviPageTransitionsBuilder();

  static const _push = CupertinoPageTransitionsBuilder();
  static const _desktop = FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!context.motionFull) {
      return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
    }
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.linux || TargetPlatform.windows => true,
      _ => false,
    };
    return (desktop ? _desktop : _push).buildTransitions<T>(route, context, animation, secondaryAnimation, child);
  }
}
