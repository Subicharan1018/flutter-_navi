import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';

/// A small line of [values] that draws itself left to right and ends on a dot.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color? color;
  final Animation<double>? progress;

  const Sparkline({super.key, required this.values, this.height = 40, this.color, this.progress});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    final t = ThemeTokens.of(context);
    final ink = color ?? t.accent;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ExcludeSemantics(
        child: PlayOnce(
          progress: progress,
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeInOutCubic,
          builder: (context, p) => AnimatedBuilder(
            animation: p,
            builder: (context, _) => CustomPaint(painter: SparklinePainter(values, ink, p.value)),
          ),
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color ink;
  final double t;
  const SparklinePainter(this.values, this.ink, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    var lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    Offset at(int i) => Offset(
          pad + (size.width - pad * 2) * i / (values.length - 1),
          pad + (size.height - pad * 2) * (1 - (values[i] - lo) / span),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    final drawn = Path();
    var left = total * t;
    Offset? head;
    for (final PathMetric m in metrics) {
      final take = left.clamp(0.0, m.length);
      drawn.addPath(m.extractPath(0, take), Offset.zero);
      head = m.getTangentForOffset(take)?.position ?? head;
      left -= take;
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
    if (head != null && t > 0) canvas.drawCircle(head, 3.5, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(SparklinePainter old) => old.t != t || old.ink != ink || old.values != values;
}
