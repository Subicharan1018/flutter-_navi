import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../motion/play_once.dart';
import 'blur_ground.dart';

/// Highlights as one calm signal over the song it came from: a single white
/// line across a soft ground of the lead cover, with the tallest peak marked
/// by one dot. A playhead sweeps once, lighting the line as it passes, then
/// it holds. Nothing else is drawn.
class PeakWave extends StatelessWidget {
  final String? coverUrl;
  final double size;
  final double radius;
  const PeakWave({super.key, required this.size, this.coverUrl, this.radius = 0});

  static const double _peak = 0.56;

  static double _y(double x) =>
      0.56 -
      0.04 * math.sin(x * 12) -
      0.03 * math.sin(x * 27 + 1) -
      0.14 * math.exp(-math.pow((x - 0.24) / 0.06, 2)) -
      0.26 * math.exp(-math.pow((x - _peak) / 0.055, 2)) -
      0.12 * math.exp(-math.pow((x - 0.82) / 0.05, 2));

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(child: BlurGround(url: coverUrl, scrim: 0.55)),
            Positioned.fill(
              child: PlayOnce(
                duration: const Duration(milliseconds: 1800),
                curve: Curves.easeInOutCubic,
                builder: (context, p) => AnimatedBuilder(
                  animation: p,
                  builder: (context, _) => CustomPaint(painter: _WavePainter(t.accent, p.value)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color lit;
  final double t;
  const _WavePainter(this.lit, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final x = i / 120;
      final o = Offset(x * size.width, PeakWave._y(x) * size.height);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.014;
    canvas.drawPath(path, stroke..color = lit.withValues(alpha: 0.3));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    canvas.drawPath(path, stroke..color = lit);
    canvas.restore();
    if (t >= PeakWave._peak) {
      canvas.drawCircle(
        Offset(size.width * PeakWave._peak, PeakWave._y(PeakWave._peak) * size.height),
        size.width * 0.026,
        Paint()..color = lit,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.lit != lit;
}
