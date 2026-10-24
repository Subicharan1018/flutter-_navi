import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';

/// A thin ring that sweeps to [value] (0..1) with the figure it stands for in
/// the middle. Used for skip rate, completion and the like.
class RingGauge extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? center;
  final String? semanticLabel;
  final Animation<double>? progress;

  const RingGauge({
    super.key,
    required this.value,
    this.size = 64,
    this.stroke = 5,
    this.color,
    this.center,
    this.semanticLabel,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final ink = color ?? t.accent;
    final target = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel ?? '${(target * 100).round()} percent',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: PlayOnce(
          progress: progress,
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutQuart,
          builder: (context, p) => AnimatedBuilder(
            animation: p,
            builder: (context, _) => CustomPaint(
              painter: RingPainter(sweep: target * p.value, track: t.fill, ink: ink, stroke: stroke),
              child: Center(child: center),
            ),
          ),
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  final double sweep;
  final Color track;
  final Color ink;
  final double stroke;
  const RingPainter({required this.sweep, required this.track, required this.ink, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    if (sweep > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * sweep, false, base..color = ink);
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.sweep != sweep || old.track != track || old.ink != ink || old.stroke != stroke;
}
