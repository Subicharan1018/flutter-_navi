import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../art/navi_icons.dart';

/// Wraps a like / favourite control: when [active] turns on, the control pops
/// and a ring of small hearts (our own glyph) flies outward and fades. Nothing
/// plays when it turns off, on first build, or under Reduced motion.
class HeartBurst extends StatefulWidget {
  final bool active;
  final Color color;
  final Widget child;
  const HeartBurst({super.key, required this.active, required this.color, required this.child});

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  /// The control swells and settles in the burst's first half.
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.22).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0).chain(CurveTween(curve: Motion.spring)), weight: 65),
  ]).animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.5)));

  @override
  void didUpdateWidget(HeartBurst old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && context.motionFullNow) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ScaleTransition(scale: _pop, child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: HeartBurstPainter(_c, widget.color)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Six hearts leaving the centre, shrinking and fading as they go. Paints
/// nothing while the animation is at rest.
class HeartBurstPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;
  HeartBurstPainter(this.progress, this.color) : super(repaint: progress);

  static const int count = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final out = Motion.decelerate.transform(t);
    final reach = size.shortestSide * 0.95;
    final heart = (size.shortestSide * 0.26) * (1 - 0.5 * t);
    final fade = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / count;
      final c = size.center(Offset.zero) + Offset(math.cos(angle), math.sin(angle)) * (reach * out);
      canvas
        ..save()
        ..translate(c.dx - heart / 2, c.dy - heart / 2);
      NaviGlyphPainter(NaviGlyph.heart, color.withValues(alpha: color.a * fade), true).paint(canvas, Size.square(heart));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(HeartBurstPainter old) => old.color != color || old.progress != progress;
}
