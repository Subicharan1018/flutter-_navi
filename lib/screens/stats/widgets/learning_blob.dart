import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/ambient_loop.dart';

/// A liquid drop that stands for the Smart Shuffle model: it is as big as the
/// share of the next rebuild already collected, and while [alive] its edge
/// slowly morphs. Only the painter's path changes (one small shape under its
/// own RepaintBoundary, about 30 fps, only while on screen with Motion Full);
/// when not running it holds a calm, finished silhouette.
class LearningBlob extends StatelessWidget {
  /// 0→1 share of the way to the next rebuild.
  final double fill;
  final bool alive;
  const LearningBlob({super.key, required this.fill, required this.alive});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    Widget paint(double phase) => CustomPaint(
      painter: _BlobPainter(t.accent, t.fill, fill.clamp(0.0, 1.0), phase),
      size: Size.infinite,
    );
    if (!alive) return RepaintBoundary(child: paint(0.25));
    return AmbientLoop(period: const Duration(seconds: 9), builder: (context, phase) => paint(phase));
  }
}

class _BlobPainter extends CustomPainter {
  final Color ink;
  final Color well;
  final double fill;
  final double phase;
  const _BlobPainter(this.ink, this.well, this.fill, this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    // The well: where the drop can grow to.
    canvas.drawCircle(c, maxR, Paint()..color = well);
    final base = maxR * (0.34 + 0.56 * fill);
    const n = 8;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        c +
            Offset.fromDirection(
              i / n * 2 * math.pi,
              base * (1 + 0.10 * math.sin(phase * 2 * math.pi + i * 1.7) + 0.05 * math.sin(phase * 4 * math.pi + i * 0.9)),
            ),
    ];
    // Closed Catmull-Rom spline through the points.
    final path = Path()..moveTo((pts[0].dx + pts[n - 1].dx) / 2, (pts[0].dy + pts[n - 1].dy) / 2);
    for (var i = 0; i < n; i++) {
      final p = pts[i];
      final q = pts[(i + 1) % n];
      path.quadraticBezierTo(p.dx, p.dy, (p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
    }
    canvas.drawPath(path, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.phase != phase || old.fill != fill || old.ink != ink || old.well != well;
}
