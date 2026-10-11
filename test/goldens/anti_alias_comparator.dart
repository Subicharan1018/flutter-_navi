// Golden comparison that ignores anti-aliasing and nothing else.
//
// Text and icon edges are rasterised slightly differently on each machine
// (font backend, hinting, Flutter engine build), so a pixel-exact comparison
// fails on every machine except the one that recorded the golden — while a
// percentage threshold would hide real regressions (a changed icon is ~0.03%
// of a phone screen). Two rules, both local to a pixel's 3×3 neighbourhood:
//
//   1. pixelmatch's anti-aliasing test (mapbox/pixelmatch, ISC): a differing
//      pixel that is an anti-aliased blend across a stable edge is ignored.
//   2. hinting shift: font hinting can snap a glyph stem one pixel left or
//      right, turning a pixel fully on/off. Ignored only when each image's
//      colour appears within one pixel in the *other* image — true for a
//      1 px shift, false inside anything added, removed or recoloured.
//
//   3. specks: what survives 1–2 is grouped into 8-connected clusters, and a
//      cluster counts only above [minCluster] pixels. Measured across this
//      suite on two machines, rasteriser leftovers are isolated specks of at
//      most 12 px; replacing one queue icon produced clusters of 44–317 px.
//      24 px is ~3×3 pt at the 3× test resolution — below anything a person
//      would see as a change.
//
// Moved (>1 px), recoloured or missing content still fails.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smallest cluster of differing pixels that counts as a real change.
const int minCluster = 24;

/// Result of an anti-alias-aware comparison.
class PixelDiff {
  final int width;
  final int height;

  /// Pixels that differ, are not anti-aliasing/hinting, and form a cluster
  /// larger than [minCluster].
  final int different;

  /// Pixels ignored: anti-aliasing, 1 px hinting shifts, isolated specks.
  final int antiAliased;

  const PixelDiff(this.width, this.height, this.different, this.antiAliased);

  bool get sizeMatches => width > 0;
}

/// Colour difference below which pixels are equal (pixelmatch's default 0.1,
/// on its YIQ scale where 35215 is the maximum squared delta).
const double _threshold = 0.1;
const double _maxDelta = 35215 * _threshold * _threshold;

Future<PixelDiff> comparePng(Uint8List a, Uint8List b) async {
  final ia = await _decode(a);
  final ib = await _decode(b);
  if (ia.width != ib.width || ia.height != ib.height) return const PixelDiff(0, 0, 1, 0);
  final w = ia.width, h = ia.height;
  var aa = 0;
  final candidates = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final pos = (y * w + x) * 4;
      final delta = _colorDelta(ia.rgba, ib.rgba, pos, pos, false);
      if (delta.abs() > _maxDelta) {
        if (_antialiased(ia, x, y, ib) || _antialiased(ib, x, y, ia) ||
            (_nearMatch(ia, pos, ib, x, y) && _nearMatch(ib, pos, ia, x, y))) {
          aa++;
        } else {
          candidates.add(y * w + x);
        }
      }
    }
  }
  // Rule 3: only clusters larger than [minCluster] are real changes.
  var diff = 0;
  final seen = <int>{};
  for (final start in candidates) {
    if (!seen.add(start)) continue;
    var size = 0;
    final stack = [start];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final x = p % w, y = p ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final q = ny * w + nx;
          if (candidates.contains(q) && seen.add(q)) stack.add(q);
        }
      }
    }
    if (size > minCluster) {
      diff += size;
    } else {
      aa += size;
    }
  }
  return PixelDiff(w, h, diff, aa);
}

class _Img {
  final int width, height;
  final Uint8List rgba;
  _Img(this.width, this.height, this.rgba);
}

Future<_Img> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final img = _Img(image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  return img;
}

/// Is (x1, y1) of [img] an anti-aliased pixel? (pixelmatch `antialiased`)
bool _antialiased(_Img img, int x1, int y1, _Img img2) {
  final w = img.width, h = img.height;
  final x0 = math.max(x1 - 1, 0), y0 = math.max(y1 - 1, 0);
  final x2 = math.min(x1 + 1, w - 1), y2 = math.min(y1 + 1, h - 1);
  final pos = (y1 * w + x1) * 4;
  var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0;
  double min = 0, max = 0;
  int minX = 0, minY = 0, maxX = 0, maxY = 0;

  for (var x = x0; x <= x2; x++) {
    for (var y = y0; y <= y2; y++) {
      if (x == x1 && y == y1) continue;
      final delta = _colorDelta(img.rgba, img.rgba, pos, (y * w + x) * 4, true);
      if (delta == 0) {
        zeroes++;
        if (zeroes > 2) return false; // flat area: a real edge, not AA
      } else if (delta < min) {
        min = delta;
        minX = x;
        minY = y;
      } else if (delta > max) {
        max = delta;
        maxX = x;
        maxY = y;
      }
    }
  }
  if (min == 0 || max == 0) return false; // no darker and brighter neighbour
  // AA when the darkest or the brightest neighbour sits in a flat region of
  // both images (so the pixel is a blend across a stable edge).
  return (_hasManySiblings(img, minX, minY) && _hasManySiblings(img2, minX, minY)) ||
      (_hasManySiblings(img, maxX, maxY) && _hasManySiblings(img2, maxX, maxY));
}

/// Does the colour at [pos] of [src] occur within one pixel of (x, y) in [dst]?
bool _nearMatch(_Img src, int pos, _Img dst, int x, int y) {
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= dst.width || ny >= dst.height) continue;
      if (_colorDelta(src.rgba, dst.rgba, pos, (ny * dst.width + nx) * 4, false).abs() <= _maxDelta) {
        return true;
      }
    }
  }
  return false;
}

bool _hasManySiblings(_Img img, int x1, int y1) {
  final w = img.width, h = img.height;
  final x0 = math.max(x1 - 1, 0), y0 = math.max(y1 - 1, 0);
  final x2 = math.min(x1 + 1, w - 1), y2 = math.min(y1 + 1, h - 1);
  final pos = (y1 * w + x1) * 4;
  var zeroes = (x1 == x0 || x1 == x2 || y1 == y0 || y1 == y2) ? 1 : 0;
  final d = img.rgba;
  for (var x = x0; x <= x2; x++) {
    for (var y = y0; y <= y2; y++) {
      if (x == x1 && y == y1) continue;
      final p2 = (y * w + x) * 4;
      if (d[pos] == d[p2] && d[pos + 1] == d[p2 + 1] && d[pos + 2] == d[p2 + 2] && d[pos + 3] == d[p2 + 3]) {
        zeroes++;
      }
      if (zeroes > 2) return true;
    }
  }
  return false;
}

/// Squared YIQ distance (pixelmatch `colorDelta`); with [yOnly], the signed
/// brightness difference.
double _colorDelta(Uint8List a, Uint8List b, int k, int m, bool yOnly) {
  var r1 = a[k].toDouble(), g1 = a[k + 1].toDouble(), b1 = a[k + 2].toDouble();
  var r2 = b[m].toDouble(), g2 = b[m + 1].toDouble(), b2 = b[m + 2].toDouble();
  final a1 = a[k + 3], a2 = b[m + 3];
  if (a1 == a2 && r1 == r2 && g1 == g2 && b1 == b2) return 0;
  if (a1 < 255) {
    final f = a1 / 255;
    r1 = 255 + (r1 - 255) * f;
    g1 = 255 + (g1 - 255) * f;
    b1 = 255 + (b1 - 255) * f;
  }
  if (a2 < 255) {
    final f = a2 / 255;
    r2 = 255 + (r2 - 255) * f;
    g2 = 255 + (g2 - 255) * f;
    b2 = 255 + (b2 - 255) * f;
  }
  final y1 = r1 * 0.29889531 + g1 * 0.58662247 + b1 * 0.11448223;
  final y2 = r2 * 0.29889531 + g2 * 0.58662247 + b2 * 0.11448223;
  final y = y1 - y2;
  if (yOnly) return y;
  final i = (r1 * 0.59597799 - g1 * 0.27417610 - b1 * 0.32180189) -
      (r2 * 0.59597799 - g2 * 0.27417610 - b2 * 0.32180189);
  final q = (r1 * 0.21147017 - g1 * 0.52261711 + b1 * 0.31114694) -
      (r2 * 0.21147017 - g2 * 0.52261711 + b2 * 0.31114694);
  final delta = 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q;
  return y1 > y2 ? -delta : delta;
}

/// [LocalFileComparator] that passes when the only differences are
/// anti-aliasing, and otherwise fails with the usual diff images plus the
/// count of real differing pixels.
class AntiAliasTolerantComparator extends LocalFileComparator {
  AntiAliasTolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = await getGoldenBytes(golden);
    final exact = await GoldenFileComparator.compareLists(imageBytes, goldenBytes);
    if (exact.passed) {
      exact.dispose();
      return true;
    }
    final d = await comparePng(imageBytes, Uint8List.fromList(goldenBytes));
    if (d.sizeMatches && d.different == 0) {
      debugPrint('[golden] $golden: ${d.antiAliased} rasteriser-noise pixels ignored');
      exact.dispose();
      return true;
    }
    final error = await generateFailureOutput(exact, golden, basedir);
    exact.dispose();
    throw FlutterError(d.sizeMatches
        ? '$error\n${d.different} pixels differ beyond anti-aliasing '
            '(${d.antiAliased} rasteriser-noise pixels ignored).'
        : '$error\nImage sizes differ.');
  }
}
