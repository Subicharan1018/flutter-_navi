import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../motion/play_once.dart';

/// Highlights as one signal: a quiet line across a dark ground whose peaks
/// light up white as a playhead sweeps past, the way a saved moment is a peak
/// in the song. Sweeps once, then holds the lit shape.
class PeakWave extends StatelessWidget {
  final double size;
  final double radius;
  const PeakWave({super.key, required this.size, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.bgElevated,
        child: SizedBox.square(
          dimension: size,
          child: PlayOnce(
            duration: const Duration(milliseconds: 1800),
            curve: Curves.easeInOutCubic,
            builder: (context, p) => AnimatedBuilder(
              animation: p,
              builder: (context, _) => CustomPaint(painter: _WavePainter(t.textMuted, t.accent, p.value)),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color quiet;
  final Color lit;
  final double t;
  const _WavePainter(this.quiet, this.lit, this.t);

  static double _y(double x) =>
      0.5 -
      0.07 * math.sin(x * 14) -
      0.05 * math.sin(x * 31 + 1) -
      0.30 * math.exp(-math.pow((x - 0.28) / 0.05, 2)) +
      0.22 * math.exp(-math.pow((x - 0.55) / 0.045, 2)) -
      0.36 * math.exp(-math.pow((x - 0.78) / 0.04, 2));

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final x = i / 120;
      final o = Offset(x * size.width, _y(x) * size.height);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.018;
    canvas.drawPath(path, stroke..color = quiet.withValues(alpha: 0.5));
    final head = size.width * t;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, head, size.height));
    canvas.drawPath(path, stroke..color = lit);
    canvas.restore();
    if (t < 1) {
      canvas.drawRect(Rect.fromLTWH(head - 0.75, size.height * 0.12, 1.5, size.height * 0.76), Paint()..color = lit);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.quiet != quiet || old.lit != lit;
}
