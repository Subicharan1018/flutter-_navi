import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'microduck_pose.dart';

/// Draws Microduck in the app icons' line style: a 24 x 24 grid, rounded
/// caps and joins, one colour. Everything is a function of [pose] and the
/// seconds on [time], so the painter itself holds no animation state.
///
/// The Paint objects and the Path are reused between frames, so painting
/// allocates nothing but a few Offsets/Rects.
class MicroduckPainter extends CustomPainter {
  final MicroduckPose pose;
  final ValueListenable<double> time;
  final Color color;

  /// Seconds per beat while dancing.
  final double beat;

  /// 1 = full hop, lower for a gentle bob when the tempo is unknown.
  final double energy;

  final bool facingRight;

  MicroduckPainter({
    required this.pose,
    required this.time,
    required this.color,
    this.beat = 0.5,
    this.energy = 1,
    this.facingRight = true,
  }) : super(repaint: time);

  static const double _grid = 24;
  static const double _stroke = 1.75;

  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _dot = Paint()..style = PaintingStyle.fill;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final s = math.min(size.width, size.height) / _grid;
    if (s <= 0) return;

    _line
      ..color = color
      ..strokeWidth = _stroke;
    _dot.color = color;

    canvas.save();
    canvas.translate((size.width - _grid * s) / 2, (size.height - _grid * s) / 2);
    canvas.scale(s);
    if (!facingRight) {
      canvas.translate(_grid, 0);
      canvas.scale(-1, 1);
    }

    // Per-pose body motion.
    double dy = 0;
    double tilt = 0;
    double hx = 16.5, hy = 6.5; // head centre
    var blink = false;
    var wing = 0.0; // wing lift, -1..1
    var stride = 0.0; // leg phase, radians
    var legs = true;

    switch (pose) {
      case MicroduckPose.idle:
        dy = math.sin(t * 1.6) * 0.15;
        blink = (t % 3.6) < 0.14;
      case MicroduckPose.run:
        stride = t * 13;
        dy = -(math.sin(stride).abs()) * 0.9;
        tilt = 0.06;
        wing = math.sin(stride);
        hx += 0.4;
      case MicroduckPose.sleep:
        dy = 2.6 + math.sin(t * 1.2) * 0.22;
        hx = 14.6;
        hy = 8.6;
        blink = true;
        legs = false;
      case MicroduckPose.dance:
        final beats = t / beat;
        final phase = beats % 1;
        final strong = (beats.floor() % 4) == 0;
        final hop = math.sin(math.pi * phase).abs();
        dy = -hop * (strong ? 2.1 : 1.3) * energy;
        tilt = math.sin(math.pi * beats) * 0.12 * energy;
        wing = -1 + 2 * hop;
        blink = phase > 0.8 && !strong;
    }

    canvas.save();
    canvas.translate(12, 12);
    canvas.rotate(tilt);
    canvas.translate(-12, -12 + dy);

    // Body and head as one outline.
    final cx = hx, cy = hy;
    final headRect = Rect.fromCircle(center: Offset(cx, cy), radius: 3.4);
    final chestX = cx + 1.7, chestY = cy + 2.94;
    _path
      ..reset()
      ..moveTo(3, 10.5)
      ..cubicTo(5, 14.5, 8, 17.5, 12.5, 17.5)
      ..cubicTo(16.5, 17.5, 18.8, 15, 18.6, 12.2)
      ..cubicTo(18.55, 11.2, chestX + 0.6, chestY + 1.4, chestX, chestY)
      ..arcTo(headRect, math.pi / 3, -1.5 * math.pi, false)
      ..cubicTo(cx - 4.5, cy + 3.2, 10, 9.8, 3, 10.5);
    canvas.drawPath(_path, _line);

    // Beak.
    final bx = cx + 3.3;
    final by = cy + 0.4 + (pose == MicroduckPose.sleep ? 0.5 : 0);
    _path
      ..reset()
      ..moveTo(bx, by - 1)
      ..lineTo(bx + 2.5, by + 0.1)
      ..lineTo(bx - 0.1, by + 1.1);
    canvas.drawPath(_path, _line);

    // Eye: a dot, or a closed lid while blinking and asleep.
    final ex = cx + 1.1, ey = cy - 0.7;
    if (blink) {
      _path
        ..reset()
        ..moveTo(ex - 0.8, ey)
        ..quadraticBezierTo(ex, ey + 0.9, ex + 0.8, ey);
      canvas.drawPath(_path, _line..strokeWidth = 1.4);
      _line.strokeWidth = _stroke;
    } else {
      canvas.drawCircle(Offset(ex, ey), 0.7, _dot);
    }

    // Wing.
    final lift = wing * 1.4;
    _path
      ..reset()
      ..moveTo(8.2, 12.6)
      ..quadraticBezierTo(11, 15.4 - lift, 14.2, 12.6 - lift * 0.6);
    canvas.drawPath(_path, _line);

    // Legs: stand, or scissor while running.
    if (legs) {
      _leg(canvas, 10.4, pose == MicroduckPose.run ? math.sin(stride) : 0, pose == MicroduckPose.run ? math.cos(stride) : 0);
      _leg(canvas, 14.2, pose == MicroduckPose.run ? -math.sin(stride) : 0, pose == MicroduckPose.run ? -math.cos(stride) : 0);
    }
    canvas.restore();

    // Accents sit in the grid, not on the bobbing body.
    if (pose == MicroduckPose.sleep) _zzz(canvas, t);
    if (pose == MicroduckPose.dance) _notes(canvas, t / beat);

    canvas.restore();
  }

  /// One leg from the belly (y 17.5 minus the body bounce) to the ground at y
  /// 21; [swing] moves the foot fore/aft, [lift] raises it off the ground.
  void _leg(Canvas canvas, double hipX, double swing, double lift) {
    final footX = hipX + swing * 2.4;
    final footY = 21.2 - math.max(0, lift) * 1.6;
    _path
      ..reset()
      ..moveTo(hipX, 17.4)
      ..lineTo(footX, footY)
      ..lineTo(footX + 1.6, footY);
    canvas.drawPath(_path, _line);
  }

  /// Three z's rising and fading in a loop.
  void _zzz(Canvas canvas, double t) {
    for (var i = 0; i < 3; i++) {
      final p = ((t / 3.2) + i / 3) % 1;
      final size = 1.6 + p * 1.6;
      final x = 17.5 + p * 3 + i * 0.2;
      final y = 6 - p * 4.5;
      final a = (p < 0.15 ? p / 0.15 : (1 - p) / 0.85).clamp(0.0, 1.0);
      _line
        ..color = color.withValues(alpha: a)
        ..strokeWidth = 1.3;
      _path
        ..reset()
        ..moveTo(x, y)
        ..lineTo(x + size, y)
        ..lineTo(x, y + size)
        ..lineTo(x + size, y + size);
      canvas.drawPath(_path, _line);
    }
    _line
      ..color = color
      ..strokeWidth = _stroke;
  }

  /// Eighth-note marks that float up from either side on each beat.
  void _notes(Canvas canvas, double beats) {
    for (var i = 0; i < 2; i++) {
      final p = ((beats / 2) + i * 0.5) % 1;
      final left = i == 0;
      final x = left ? 3.2 - p * 1.2 : 20.4 + p * 1.2;
      final y = 9 - p * 7;
      final a = (p < 0.2 ? p / 0.2 : (1 - p) / 0.8).clamp(0.0, 1.0);
      _line
        ..color = color.withValues(alpha: a)
        ..strokeWidth = 1.3;
      _dot.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 0.9, _dot);
      _path
        ..reset()
        ..moveTo(x + 0.9, y)
        ..lineTo(x + 0.9, y - 3.2)
        ..lineTo(x + 2.4, y - 2.4);
      canvas.drawPath(_path, _line);
    }
    _line
      ..color = color
      ..strokeWidth = _stroke;
    _dot.color = color;
  }

  @override
  bool shouldRepaint(MicroduckPainter old) =>
      old.pose != pose ||
      old.color != color ||
      old.beat != beat ||
      old.energy != energy ||
      old.facingRight != facingRight ||
      old.time != time;
}
