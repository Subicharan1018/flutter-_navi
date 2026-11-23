import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../motion/play_once.dart';

/// Start Listening as paths crossing: three lines that swap places on a white
/// ground, with a dot travelling each one to the far side. Travels once, then
/// rests at the end of its line.
class ShuffleTrails extends StatelessWidget {
  final double size;
  final double radius;
  const ShuffleTrails({super.key, required this.size, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: t.accent,
        child: SizedBox.square(
          dimension: size,
          child: PlayOnce(
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOutCubic,
            builder: (context, p) => AnimatedBuilder(
              animation: p,
              builder: (context, _) => CustomPaint(painter: _TrailsPainter(t.onAccent, p.value)),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailsPainter extends CustomPainter {
  final Color ink;
  final double t;
  const _TrailsPainter(this.ink, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Left row to right row, each ending where another began.
    const from = [0.28, 0.5, 0.72];
    const to = [0.72, 0.28, 0.5];
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.028
      ..color = ink.withValues(alpha: 0.9);
    final dot = Paint()..color = ink;
    for (var i = 0; i < 3; i++) {
      final a = Offset(w * 0.14, h * from[i]);
      final b = Offset(w * 0.86, h * to[i]);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(w * 0.5, a.dy, w * 0.5, b.dy, b.dx, b.dy);
      canvas.drawPath(path, line);
      canvas.drawCircle(a, w * 0.032, dot);
      final m = path.computeMetrics().first;
      final k = Curves.easeInOutCubic.transform(((t - i * 0.12) / 0.76).clamp(0.0, 1.0));
      final pos = m.getTangentForOffset(m.length * k)!.position;
      canvas.drawCircle(pos, w * 0.05, dot);
    }
  }

  @override
  bool shouldRepaint(_TrailsPainter old) => old.t != t || old.ink != ink;
}
