import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'cover_motifs.dart';

// =============================================================================
// NaviVibe's own cover art for anything without a real cover: playlists, mixes,
// Discover and Trending shelves.
//
// A cover is a pure function of its seed string, so the same playlist always
// looks the same on every device and every launch. Twelve motifs, all drawn from
// sound and signal: waveform, halftone, vinyl grooves, scan lines (here) and
// spiral, grid-warp, stripes, dots-on-circle, contour, orbit, radial bars and
// tessellation (cover_motifs.dart) — on a grey ground with white (or, for a quarter of seeds, near-black)
// ink and a fine grain. No hues: the album-driven accent stays the app's only
// colour.
// =============================================================================

enum CoverMotif {
  waveform,
  halftone,
  grooves,
  scan,
  spiral,
  gridWarp,
  stripes,
  dotsOnCircle,
  contour,
  orbit,
  radialBars,
  tessellation,
}

/// Builds the seed for a cover from what identifies the collection. Song ids
/// make two playlists with the same name still differ; only the first few are
/// used so adding a track to a long playlist doesn't redraw its cover.
String coverSeed(String name, [Iterable<String> songIds = const []]) {
  final ids = songIds.take(6).join(',');
  return '${name.trim().toLowerCase()}|$ids';
}

/// Everything the painter needs, derived deterministically from a seed.
@immutable
class GeneratedCoverSpec {
  static const int sampleCount = 33;

  final String seed;
  final CoverMotif motif;

  /// Smoothed 0..1 samples that shape bars, dots and scan lines.
  final List<double> samples;

  /// Focal point of the motif, 0..1 in each axis.
  final double focusX;
  final double focusY;

  /// Dark ink on a light ground instead of light ink on a dark ground.
  final bool inverted;

  /// 0..1 grey level of the ground before inversion.
  final double ground;

  final int grainSeed;

  const GeneratedCoverSpec._({
    required this.seed,
    required this.motif,
    required this.samples,
    required this.focusX,
    required this.focusY,
    required this.inverted,
    required this.ground,
    required this.grainSeed,
  });

  static final Map<String, GeneratedCoverSpec> _cache = {};

  /// Specs are tiny but every shelf tile asks for one on each build, so the
  /// recent ones are memoised.
  factory GeneratedCoverSpec.fromSeed(String seed) {
    final hit = _cache.remove(seed);
    if (hit != null) {
      _cache[seed] = hit;
      return hit;
    }
    final spec = derive(seed);
    _cache[seed] = spec;
    if (_cache.length > 256) _cache.remove(_cache.keys.first);
    return spec;
  }

  @visibleForTesting
  static GeneratedCoverSpec derive(String seed) {
    final rng = _Mulberry32(fnv1a(seed));
    final motif = CoverMotif.values[rng.nextInt(CoverMotif.values.length)];
    final raw = List<double>.generate(sampleCount, (_) => rng.nextDouble());
    // Two box-blur passes turn noise into something that reads as a signal.
    final samples = _smooth(_smooth(raw));
    return GeneratedCoverSpec._(
      seed: seed,
      motif: motif,
      samples: samples,
      focusX: 0.25 + rng.nextDouble() * 0.5,
      focusY: 0.25 + rng.nextDouble() * 0.5,
      inverted: rng.nextDouble() < 0.25,
      ground: 0.10 + rng.nextDouble() * 0.10,
      grainSeed: rng.nextInt(1 << 30),
    );
  }

  static List<double> _smooth(List<double> v) {
    final out = List<double>.filled(v.length, 0);
    for (var i = 0; i < v.length; i++) {
      final a = v[math.max(0, i - 1)];
      final c = v[math.min(v.length - 1, i + 1)];
      out[i] = (a + 2 * v[i] + c) / 4;
    }
    // Stretch back to the full 0..1 range so every cover has real contrast.
    final lo = out.reduce(math.min);
    final hi = out.reduce(math.max);
    final span = math.max(hi - lo, 1e-6);
    return [for (final x in out) (x - lo) / span];
  }

  Color get groundColor {
    final g = inverted ? 0.86 - ground * 0.3 : ground;
    final c = (g * 255).round();
    return Color.fromARGB(255, c, c, c);
  }

  Color get inkColor =>
      inverted ? const Color(0xFF0C0C0C) : const Color(0xFFF4F4F4);

  @override
  bool operator ==(Object other) =>
      other is GeneratedCoverSpec && other.seed == seed;

  @override
  int get hashCode => seed.hashCode;
}

/// 32-bit FNV-1a: stable across platforms and runs, unlike `String.hashCode`.
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

class _Mulberry32 {
  int _a;
  _Mulberry32(int seed) : _a = seed & 0xFFFFFFFF;

  double nextDouble() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _a;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    return (((t ^ (t >>> 14)) & 0xFFFFFFFF)) / 4294967296.0;
  }

  int nextInt(int max) => (nextDouble() * max).floor();

  static int _imul(int a, int b) =>
      ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

/// A generated cover. Isolated in its own layer: it never changes after the
/// first paint, so it is rasterised once and reused while lists scroll.
class GeneratedCover extends StatelessWidget {
  final String seed;

  /// Convenience: build the seed from a name and the collection's song ids.
  GeneratedCover({
    super.key,
    required String name,
    Iterable<String> songIds = const [],
    this.borderRadius = 0,
  }) : seed = coverSeed(name, songIds);

  const GeneratedCover.seeded({
    super.key,
    required this.seed,
    this.borderRadius = 0,
  });

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final art = RepaintBoundary(
      child: CustomPaint(
        painter: GeneratedCoverPainter(GeneratedCoverSpec.fromSeed(seed)),
        child: const SizedBox.expand(),
      ),
    );
    if (borderRadius <= 0) return art;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: art,
    );
  }
}

class GeneratedCoverPainter extends CustomPainter {
  final GeneratedCoverSpec spec;
  const GeneratedCoverPainter(this.spec);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final small = math.min(w, h) < 80;
    final ink = spec.inkColor;

    canvas.drawRect(Offset.zero & size, Paint()..color = spec.groundColor);

    switch (spec.motif) {
      case CoverMotif.waveform:
        _waveform(canvas, w, h, small, ink);
      case CoverMotif.halftone:
        _halftone(canvas, w, h, small, ink);
      case CoverMotif.grooves:
        _grooves(canvas, w, h, small, ink);
      case CoverMotif.scan:
        _scan(canvas, w, h, small, ink);
      case CoverMotif.spiral:
        paintSpiral(canvas, size, spec, small, ink);
      case CoverMotif.gridWarp:
        paintGridWarp(canvas, size, spec, small, ink);
      case CoverMotif.stripes:
        paintStripes(canvas, size, spec, small, ink);
      case CoverMotif.dotsOnCircle:
        paintDotsOnCircle(canvas, size, spec, small, ink);
      case CoverMotif.contour:
        paintContour(canvas, size, spec, small, ink);
      case CoverMotif.orbit:
        paintOrbit(canvas, size, spec, small, ink);
      case CoverMotif.radialBars:
        paintRadialBars(canvas, size, spec, small, ink);
      case CoverMotif.tessellation:
        paintTessellation(canvas, size, spec, small, ink);
    }
    if (!small) _grain(canvas, w, h, ink);
  }

  double _s(int i) => spec.samples[i % GeneratedCoverSpec.sampleCount];

  void _waveform(Canvas canvas, double w, double h, bool small, Color ink) {
    final bars = small ? 7 : 15;
    final step = w / bars;
    final mid = h * (0.38 + spec.focusY * 0.24);
    final paint = Paint()..color = ink;
    for (var i = 0; i < bars; i++) {
      final v = _s(i * 2);
      final bh = h * (0.07 + 0.58 * v);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(step * (i + 0.5), mid),
          width: step * 0.52,
          height: bh,
        ),
        Radius.circular(step * 0.26),
      );
      canvas.drawRRect(rect, paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, mid + h * 0.36, w, math.max(1, h * 0.006)),
      Paint()..color = ink.withValues(alpha: 0.35),
    );
  }

  void _halftone(Canvas canvas, double w, double h, bool small, Color ink) {
    final cols = small ? 6 : 11;
    final cell = w / cols;
    final rows = (h / cell).ceil();
    final fx = spec.focusX * w;
    final fy = spec.focusY * h;
    final reach = math.sqrt(w * w + h * h) * 0.62;
    final paint = Paint()..color = ink;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = cell * (c + 0.5);
        final cy = cell * (r + 0.5);
        final d = (Offset(cx, cy) - Offset(fx, fy)).distance / reach;
        final wobble = 0.82 + 0.36 * _s(r * cols + c);
        final t = (1 - d).clamp(0.0, 1.0) * wobble;
        final radius = cell * (0.06 + 0.42 * t);
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      }
    }
  }

  void _grooves(Canvas canvas, double w, double h, bool small, Color ink) {
    final centre = Offset(w * (0.3 + spec.focusX * 0.4), h * (0.3 + spec.focusY * 0.4));
    final rings = small ? 5 : 9;
    final gap = math.max(w, h) * 0.95 / rings;
    for (var i = 0; i < rings; i++) {
      final v = _s(i * 3);
      canvas.drawCircle(
        centre,
        gap * (i + 0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, gap * (0.1 + 0.5 * v))
          ..color = ink.withValues(alpha: 0.35 + 0.6 * v),
      );
    }
    canvas.drawCircle(centre, gap * 0.28, Paint()..color = ink);
  }

  void _scan(Canvas canvas, double w, double h, bool small, Color ink) {
    final lines = small ? 6 : 11;
    final steps = small ? 14 : 28;
    final gap = h / (lines + 1);
    final amp = gap * 1.7;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1, h * 0.012)
      ..color = ink;
    for (var l = 0; l < lines; l++) {
      final path = Path();
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final envelope = math.sin(math.pi * t);
        final peak = math.exp(-math.pow((t - spec.focusX) * 3.2, 2));
        final y = gap * (l + 1) -
            amp * envelope * peak * _s(s + l * 5) * (0.5 + spec.focusY);
        final x = w * t;
        s == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, stroke);
    }
  }

  void _grain(Canvas canvas, double w, double h, Color ink) {
    final rng = _Mulberry32(spec.grainSeed);
    final pts = Float32List(2 * 120);
    for (var i = 0; i < pts.length; i += 2) {
      pts[i] = rng.nextDouble() * w;
      pts[i + 1] = rng.nextDouble() * h;
    }
    canvas.drawRawPoints(
      PointMode.points,
      pts,
      Paint()
        ..strokeWidth = math.max(1, w * 0.006)
        ..strokeCap = StrokeCap.round
        ..color = ink.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(GeneratedCoverPainter old) => old.spec != spec;
}
