import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The robot's surface texture: a small tiling greyscale image of moulded
/// plastic that is multiplied over the lit vertex colours. It holds fine
/// injection-moulding grain, faint 3D-print layer lines (level, running along
/// the model's height), brushed streaks, hairline scratches and specks of
/// wear. Generated once in code (no asset), the first time a robot paints;
/// until it is ready robots draw plain.
///
/// Its average brightness is about 0.93, so the renderer lights a touch
/// brighter to compensate. Mip-mapped sampling averages it away when the
/// robot is small, so only large robots show the layer lines.
class MicroduckTexture {
  MicroduckTexture._();

  static const int size = 256;

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

    // Wrap-around value noise, so the tile has no seams.
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
    final coarse = grid(8), fine = grid(64), speckle = grid(128);
    final streak = Float64List.fromList([for (var i = 0; i < size; i++) rnd.nextDouble() - 0.5]);
    final layer = Float64List.fromList([for (var i = 0; i < size; i++) rnd.nextDouble()]);

    for (var y = 0; y < size; y++) {
      // Print layers: a groove every 4 texels, each a little different.
      final phase = (y % 4) / 4.0;
      final groove = (phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0) * (0.022 + 0.018 * layer[y]);
      for (var x = 0; x < size; x++) {
        var p = 0.935;
        p += 0.035 * lattice(8, coarse, x.toDouble(), y.toDouble());
        p += 0.05 * lattice(64, fine, x.toDouble(), y.toDouble());
        p += 0.03 * lattice(128, speckle, x.toDouble(), y.toDouble());
        p += 0.02 * streak[y]; // brushed, along x
        p -= groove;
        v[y * size + x] = p;
      }
    }
    // Hairline scratches, wrapped around the tile.
    for (var n = 0; n < 44; n++) {
      var x = rnd.nextDouble() * size, y = rnd.nextDouble() * size;
      final a = rnd.nextDouble() * math.pi;
      final len = 10 + rnd.nextInt(34);
      final depth = 0.035 + rnd.nextDouble() * 0.05;
      for (var i = 0; i < len; i++) {
        final ix = x.floor() % size, iy = y.floor() % size;
        v[iy * size + ix] -= depth;
        x += math.cos(a);
        y += math.sin(a);
      }
    }
    // Scuffs: small clusters of lighter, chipped specks.
    for (var n = 0; n < 26; n++) {
      final cx = rnd.nextInt(size), cy = rnd.nextInt(size);
      for (var i = 0; i < 9; i++) {
        final ix = (cx + rnd.nextInt(7) - 3) % size, iy = (cy + rnd.nextInt(7) - 3) % size;
        v[iy * size + ix] += 0.05;
      }
    }
    // Specks of dirt.
    for (var n = 0; n < 160; n++) {
      v[rnd.nextInt(size * size)] -= 0.08;
    }

    final out = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      // A bit more contrast than the raw pattern: weathered, not pristine.
      final b = ((0.935 + (v[i] - 0.935) * 1.5).clamp(0.0, 1.0) * 255).round();
      out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }
}
