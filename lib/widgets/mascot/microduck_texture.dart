import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The robot's surface texture: a small tiling greyscale image of moulded
/// plastic grain, faint brushed streaks, hairline scratches and a few specks,
/// multiplied over the lit vertex colours. Generated once in code (no asset),
/// the first time a robot paints; until it is ready robots draw plain.
///
/// Its average brightness is about 0.93, so the renderer lights a touch
/// brighter to compensate; on the glowing screen it reads as a pixel grain.
class MicroduckTexture {
  MicroduckTexture._();

  static const int size = 128;

  /// Texture coordinates the mesh assigns per robot unit.
  static const double meshTexelsPerUnit = 36;

  /// Texels per screen pixel to aim for: fine enough to read as grain, coarse
  /// enough not to shimmer.
  static const double texelsPerPixel = 1.2;

  static ui.Image? image;
  static final ValueNotifier<bool> ready = ValueNotifier(false);
  static Future<void>? _loading;

  /// Starts building the texture (once) and completes when it is usable.
  static Future<void> ensure() => _loading ??= _build();

  static Future<void> _build() async {
    final pixels = generate();
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.rgba8888, done.complete);
    image = await done.future;
    ready.value = true;
  }

  /// The RGBA bytes; public so tests can look at the pattern.
  static Uint8List generate() {
    final rnd = math.Random(7);
    final v = Float64List(size * size);

    // Wrap-around value noise at two scales, so the tile has no seams.
    double lattice(int cells, Float64List grid, double x, double y) {
      final fx = x / size * cells, fy = y / size * cells;
      final x0 = fx.floor(), y0 = fy.floor();
      final tx = fx - x0, ty = fy - y0;
      final sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
      double g(int i, int j) => grid[(j % cells) * cells + (i % cells)];
      final a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx;
      final b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx;
      return a + (b - a) * sy;
    }

    Float64List grid(int cells) => Float64List.fromList([for (var i = 0; i < cells * cells; i++) rnd.nextDouble() - 0.5]);
    final coarse = grid(6), fine = grid(32);
    final streak = Float64List.fromList([for (var i = 0; i < size; i++) rnd.nextDouble() - 0.5]);

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var p = 0.93;
        p += 0.035 * lattice(6, coarse, x.toDouble(), y.toDouble());
        p += 0.06 * lattice(32, fine, x.toDouble(), y.toDouble());
        p += 0.025 * streak[y]; // brushed, along x
        v[y * size + x] = p;
      }
    }
    // Hairline scratches, wrapped around the tile.
    for (var n = 0; n < 16; n++) {
      var x = rnd.nextDouble() * size, y = rnd.nextDouble() * size;
      final a = rnd.nextDouble() * math.pi;
      final len = 8 + rnd.nextInt(22);
      final depth = 0.04 + rnd.nextDouble() * 0.05;
      for (var i = 0; i < len; i++) {
        final ix = x.floor() % size, iy = y.floor() % size;
        v[iy * size + ix] -= depth;
        x += math.cos(a);
        y += math.sin(a);
      }
    }
    // Specks of wear.
    for (var n = 0; n < 60; n++) {
      v[rnd.nextInt(size * size)] += rnd.nextBool() ? 0.07 : -0.1;
    }

    final out = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      final b = (v[i].clamp(0.0, 1.0) * 255).round();
      out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }
}
