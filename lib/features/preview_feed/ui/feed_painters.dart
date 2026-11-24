import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A thin ring that fills clockwise as the 30 s clip plays (around the heart: the time left to decide).
class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;
  const RingPainter({
    required this.progress,
    required this.color,
    this.stroke = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.22);
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}

/// Bars with a fixed, song-specific shape that breathe while the clip plays. The bars already played are white, the rest dim:
/// the waveform doubles as the progress bar. [phase] runs 0 to 1 over and over; it is ignored when [animate] is false (paused,
/// or Reduced motion) and the bars rest at their own heights.
class WaveformPainter extends CustomPainter {
  final String seed;
  final double progress;
  final double phase;
  final bool animate;
  final Color color;
  static const int bars = 33;

  const WaveformPainter({
    required this.seed,
    required this.progress,
    required this.phase,
    required this.animate,
    required this.color,
  });

  /// 0.25 to 1: the same song always draws the same shape.
  static double shape(String seed, int i) {
    var h = 17;
    for (final u in seed.codeUnits) {
      h = (h * 131 + u) & 0x7fffffff;
    }
    h = (h ^ (i * 2654435761)) & 0x7fffffff;
    final r = (h % 1000) / 1000.0;
    final envelope =
        0.55 +
        0.45 * math.sin(math.pi * (i + 1) / (bars + 1)); // quieter at both ends
    return (0.25 + 0.75 * r) * envelope;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / bars;
    final w = gap * 0.52;
    for (var i = 0; i < bars; i++) {
      var h = shape(seed, i);
      if (animate) {
        h *= 0.72 + 0.28 * math.sin((phase * 2 + i * 0.21) * math.pi * 2);
      }
      final bh = math.max(3.0, size.height * h.clamp(0.0, 1.0));
      final x = gap * i + (gap - w) / 2;
      final played = (i + 0.5) / bars <= progress;
      final p = Paint()..color = played ? color : color.withValues(alpha: 0.28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - bh) / 2, w, bh),
          Radius.circular(w / 2),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.animate != animate ||
      old.seed != seed ||
      old.color != color;
}
