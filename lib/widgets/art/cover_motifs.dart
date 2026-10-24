import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'generated_cover.dart';

// The second family of cover motifs. Each is a pure function of the spec
// (samples + focus) and the canvas, drawn with a handful of primitives so a
// cover stays a few dozen draw calls.

double _s(GeneratedCoverSpec spec, int i) =>
    spec.samples[i % GeneratedCoverSpec.sampleCount];

Paint _line(Color ink, double width, [double alpha = 1]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = math.max(1, width)
  ..color = ink.withValues(alpha: alpha);

Offset _focus(GeneratedCoverSpec spec, double w, double h, [double spread = 0.4]) =>
    Offset(
      w * (0.5 + (spec.focusX - 0.5) * spread * 2),
      h * (0.5 + (spec.focusY - 0.5) * spread * 2),
    );

/// An Archimedean spiral that breathes with the samples.
void paintSpiral(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final c = _focus(spec, size.width, size.height);
  final turns = small ? 3.0 : 5.0;
  final maxR = math.max(size.width, size.height) * 0.85;
  const steps = 180;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final a = t * turns * 2 * math.pi + spec.focusX * 6;
    final r = maxR * t * (1 + 0.14 * (_s(spec, i ~/ 6) - 0.5));
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path, _line(ink, size.shortestSide * 0.028));
}

/// A square grid pushed outward around the focus, like a lens.
void paintGridWarp(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final n = small ? 6 : 10;
  final f = _focus(spec, size.width, size.height, 0.3);
  final sigma = size.shortestSide * (0.3 + 0.2 * _s(spec, 3));
  final push = size.shortestSide * 0.16;
  Offset warp(Offset p) {
    final d = p - f;
    final dist = d.distance;
    if (dist < 1e-3) return p;
    return p + d / dist * (push * math.exp(-math.pow(dist / sigma, 2)));
  }

  final paint = _line(ink, size.shortestSide * 0.012, 0.9);
  const seg = 14;
  for (var i = 0; i <= n; i++) {
    final vx = size.width * i / n;
    final hy = size.height * i / n;
    final v = Path();
    final hz = Path();
    for (var k = 0; k <= seg; k++) {
      final pv = warp(Offset(vx, size.height * k / seg));
      final ph = warp(Offset(size.width * k / seg, hy));
      k == 0 ? v.moveTo(pv.dx, pv.dy) : v.lineTo(pv.dx, pv.dy);
      k == 0 ? hz.moveTo(ph.dx, ph.dy) : hz.lineTo(ph.dx, ph.dy);
    }
    canvas.drawPath(v, paint);
    canvas.drawPath(hz, paint);
  }
}

/// Diagonal bands whose thickness follows the signal.
void paintStripes(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final bands = small ? 6 : 11;
  final diag = size.longestSide * 1.5;
  final pitch = diag / bands;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate(size.width / 2, size.height / 2);
  canvas.rotate(-0.35 - spec.focusX * 0.8);
  final paint = Paint()..color = ink;
  for (var i = 0; i < bands; i++) {
    final thick = pitch * (0.12 + 0.62 * _s(spec, i * 3));
    final x = -diag / 2 + pitch * (i + 0.5);
    canvas.drawRect(Rect.fromCenter(center: Offset(x, 0), width: thick, height: diag), paint);
  }
  canvas.restore();
}

/// Concentric rings of dots; dot size is the signal.
void paintDotsOnCircle(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final c = _focus(spec, size.width, size.height, 0.2);
  final rings = small ? 3 : 5;
  final gap = size.shortestSide * 0.5 / (rings + 0.3);
  final paint = Paint()..color = ink;
  canvas.drawCircle(c, gap * 0.3, paint);
  for (var r = 1; r <= rings; r++) {
    final count = 6 + r * 6;
    final radius = gap * r;
    final spin = spec.focusY * math.pi;
    for (var k = 0; k < count; k++) {
      final a = spin + k / count * 2 * math.pi;
      final dot = gap * (0.08 + 0.3 * _s(spec, r * 7 + k));
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * radius, dot, paint);
    }
  }
}

/// Closed wobbly rings around the focus, like a topographic map.
void paintContour(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final c = _focus(spec, size.width, size.height, 0.25);
  final rings = small ? 5 : 10;
  final maxR = size.longestSide * 0.78;
  const steps = 72;
  for (var r = 1; r <= rings; r++) {
    final base = maxR * r / rings;
    final path = Path();
    for (var i = 0; i < steps; i++) {
      final a = i / steps * 2 * math.pi;
      // Periodic noise: interpolate the samples around the circle, drifting
      // with the ring index so neighbouring rings are related, not equal.
      final x = (i / steps * 32 + r * 0.9);
      final lo = x.floor();
      final t = x - lo;
      final n = _s(spec, lo) * (1 - t) + _s(spec, lo + 1) * t;
      final rad = base * (0.72 + 0.5 * n * (0.4 + r / rings));
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, _line(ink, size.shortestSide * 0.012, 0.35 + 0.6 * r / rings));
  }
}

/// Tilted elliptical orbits, each carrying one body.
void paintOrbit(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final c = _focus(spec, size.width, size.height, 0.15);
  final count = small ? 3 : 5;
  final reach = size.shortestSide * 0.46;
  final paint = Paint()..color = ink;
  for (var i = 0; i < count; i++) {
    final rx = reach * (0.35 + 0.65 * (i + 1) / count);
    final ry = rx * (0.35 + 0.4 * _s(spec, i * 5));
    final tilt = spec.focusX * 1.6 + i * 0.55;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      _line(ink, size.shortestSide * 0.012, 0.7),
    );
    final a = _s(spec, i * 5 + 2) * 2 * math.pi;
    canvas.drawCircle(
      Offset(math.cos(a) * rx, math.sin(a) * ry),
      size.shortestSide * (0.02 + 0.02 * _s(spec, i)),
      paint,
    );
    canvas.restore();
  }
  canvas.drawCircle(c, size.shortestSide * 0.045, paint);
}

/// A spectrum wrapped into a circle.
void paintRadialBars(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final c = _focus(spec, size.width, size.height, 0.15);
  final n = small ? 20 : 40;
  final inner = size.shortestSide * 0.13;
  final span = size.shortestSide * 0.36;
  final paint = _line(ink, size.shortestSide * (small ? 0.045 : 0.026));
  for (var i = 0; i < n; i++) {
    // Mirror the samples so the first and last bars meet without a seam.
    final u = i < n / 2 ? i / (n / 2) : (n - i) / (n / 2);
    final v = _s(spec, (u * 32).round());
    final a = i / n * 2 * math.pi - math.pi / 2;
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(c + d * inner, c + d * (inner + span * (0.12 + 0.88 * v)), paint);
  }
}

/// A triangle tiling; each tile's weight is the signal.
void paintTessellation(Canvas canvas, Size size, GeneratedCoverSpec spec, bool small, Color ink) {
  final cols = small ? 4 : 7;
  final cw = size.width / cols;
  final rows = (size.height / cw).ceil();
  final fill = Paint();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = c * cw;
      final y = r * cw;
      final up = Path()
        ..moveTo(x, y + cw)
        ..lineTo(x + cw, y + cw)
        ..lineTo(x + cw, y)
        ..close();
      final down = Path()
        ..moveTo(x, y + cw)
        ..lineTo(x, y)
        ..lineTo(x + cw, y)
        ..close();
      canvas.drawPath(up, fill..color = ink.withValues(alpha: 0.08 + 0.92 * _s(spec, r * cols * 2 + c * 2)));
      canvas.drawPath(down, fill..color = ink.withValues(alpha: 0.08 + 0.92 * _s(spec, r * cols * 2 + c * 2 + 1)));
    }
  }
}
