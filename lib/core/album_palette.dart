import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show HSLColor;

/// The four colour roles NaviVibe derives from a cover, already tuned for a
/// dark UI so every consumer can use them without further correction.
///
///  * [deep]    — darkest tone; tints the app ground and sheet backgrounds.
///  * [base]    — mid tone; fills the mini player and washes the queue/lyrics.
///  * [vibrant] — the accent role: play button, progress, selection, toggles.
///                Always ≥ 4.5:1 against [deep] so it is legible as text too.
///  * [glow]    — a second hue for gradients and the artwork field highlight.
class AlbumPalette {
  final Color deep;
  final Color base;
  final Color vibrant;
  final Color glow;

  const AlbumPalette({
    required this.deep,
    required this.base,
    required this.vibrant,
    required this.glow,
  });

  /// Shown when nothing is playing or a cover has no usable pixels: the app's
  /// own green-black ramp with the brand green, so an empty player matches
  /// the chrome instead of inventing an identity.
  static const AlbumPalette fallback = AlbumPalette(
    deep: Color(0xFF050B07),
    base: Color(0xFF15261B),
    vibrant: Color(0xFF30D158),
    glow: Color(0xFF1F3326),
  );

  /// Page ground for album / playlist / artist pages (iOS 26.4 style): the
  /// cover's own hue, deep enough that white text reads at AA everywhere,
  /// muted enough that a neon cover doesn't become a neon page.
  ///
  /// Chrome never turns purple or pink: hues in 250–340° are pulled to the
  /// nearest blue or crimson and quietened, so the page still reads as
  /// "this cover's colour" without changing the app's identity per song.
  Color get ground {
    final hsl = HSLColor.fromColor(base);
    final hue = guardHue(hsl.hue);
    final saturation = guardSaturation(hue, (hsl.saturation * 0.8).clamp(0.0, 0.6));
    return HSLColor.fromAHSL(1, hue, saturation, hsl.lightness.clamp(0.13, 0.19)).toColor();
  }

  static const double _guardFrom = 250;
  static const double _guardTo = 340;

  /// Where guarded hues land: a clear blue and a clear red. Closer to the
  /// band, dark desaturated tones still read as indigo and dusty rose.
  static const double _landCool = 215;
  static const double _landWarm = 8;

  /// Just outside the band, hues are kept quiet for the same reason.
  static const double _edge = 20;
  static const double _edgeSaturation = 0.3;

  /// True for the purple–pink band the app never paints chrome in.
  static bool isGuardedHue(double hue) => hue >= _guardFrom && hue <= _guardTo;

  /// Pulls a purple or pink hue out to a clear blue or red; every other hue
  /// passes through.
  static double guardHue(double hue) {
    if (!isGuardedHue(hue)) return hue;
    return hue < (_guardFrom + _guardTo) / 2 ? _landCool : _landWarm;
  }

  /// Caps the saturation of surface tones whose hue sits just outside the
  /// band, so a blue-violet or crimson-pink cover still reads blue or red.
  static double guardSaturation(double hue, double saturation) {
    final nearCool = hue >= _guardFrom - _edge && hue < _guardFrom;
    final nearWarm = hue > _guardTo && hue <= _guardTo + _edge;
    return nearCool || nearWarm ? math.min(saturation, _edgeSaturation) : saturation;
  }

  /// Text/icon colour that sits on a [vibrant] fill.
  Color get onVibrant => vibrant.computeLuminance() > 0.42
      ? const Color(0xFF0B0B0B)
      : const Color(0xFFFFFFFF);

  static AlbumPalette lerp(AlbumPalette a, AlbumPalette b, double t) =>
      AlbumPalette(
        deep: Color.lerp(a.deep, b.deep, t)!,
        base: Color.lerp(a.base, b.base, t)!,
        vibrant: Color.lerp(a.vibrant, b.vibrant, t)!,
        glow: Color.lerp(a.glow, b.glow, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AlbumPalette &&
      other.deep == deep &&
      other.base == base &&
      other.vibrant == vibrant &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(deep, base, vibrant, glow);
}

// =============================================================================
// Extraction — pure Dart over raw RGBA bytes so it runs in a background
// isolate (`compute(extractAlbumPalette, bytes)`). palette_generator needs the
// engine image codec and therefore blocks the UI isolate for 50–200 ms per
// song; this works on a 64×64 thumbnail in ~2 ms off the main thread.
// =============================================================================

class _Hsv {
  final double h, s, v;
  const _Hsv(this.h, this.s, this.v);
}

_Hsv _toHsv(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final mx = math.max(rf, math.max(gf, bf));
  final mn = math.min(rf, math.min(gf, bf));
  final d = mx - mn;
  double h = 0;
  if (d > 1e-6) {
    if (mx == rf) {
      h = 60 * (((gf - bf) / d) % 6);
    } else if (mx == gf) {
      h = 60 * (((bf - rf) / d) + 2);
    } else {
      h = 60 * (((rf - gf) / d) + 4);
    }
  }
  if (h < 0) h += 360;
  return _Hsv(h, mx == 0 ? 0 : d / mx, mx);
}

/// HSL → ARGB int (so the isolate never needs dart:ui objects).
int _hsl(double h, double s, double l) {
  h = ((h % 360) + 360) % 360;
  s = s.clamp(0.0, 1.0);
  l = l.clamp(0.0, 1.0);
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c; g = x;
  } else if (h < 120) {
    r = x; g = c;
  } else if (h < 180) {
    g = c; b = x;
  } else if (h < 240) {
    g = x; b = c;
  } else if (h < 300) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  int ch(double v) => ((v + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | (ch(r) << 16) | (ch(g) << 8) | ch(b);
}

double _relLum(int argb) {
  double lin(int c) {
    final v = c / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }
  return 0.2126 * lin((argb >> 16) & 0xFF) +
      0.7152 * lin((argb >> 8) & 0xFF) +
      0.0722 * lin(argb & 0xFF);
}

double _contrast(int a, int b) {
  final la = _relLum(a), lb = _relLum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Returns `[deep, base, vibrant, glow]` as ARGB ints.
///
/// Hue histogram weighted by area, √saturation and value finds the colour a
/// person would name for the cover (tuned on real covers: a pale-sky pop
/// cover reads blue, not skin-tone). Monochrome covers keep their neutrality
/// instead of being forced into an arbitrary hue.
List<int> extractAlbumPalette(Uint8List rgba) {
  const bins = 24; // 15° hue buckets
  final weight = List<double>.filled(bins, 0);
  final sumH = List<double>.filled(bins, 0);
  final sumS = List<double>.filled(bins, 0);
  final sumV = List<double>.filled(bins, 0);
  final cnt = List<int>.filled(bins, 0);
  double totalV = 0, totalS = 0;
  int n = 0, colourfulPx = 0;

  for (int i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final hsv = _toHsv(rgba[i], rgba[i + 1], rgba[i + 2]);
    totalV += hsv.v;
    totalS += hsv.s;
    n++;
    if (hsv.s < 0.16 || hsv.v < 0.14) continue; // greys and near-blacks
    final b = (hsv.h / (360 / bins)).floor() % bins;
    // Area matters most: a cover that is half pale-blue sky reads as blue,
    // even if a smaller area (skin, a logo) is more saturated.
    final w = math.sqrt(hsv.s) * (0.2 + hsv.v);
    colourfulPx++;
    weight[b] += w;
    sumH[b] += hsv.h * w;
    sumS[b] += hsv.s * w;
    sumV[b] += hsv.v * w;
    cnt[b]++;
  }
  if (n == 0) return _fallbackInts;

  // Smooth neighbouring bins so a hue split across a boundary isn't halved.
  final smooth = List<double>.generate(
    bins,
    (b) => weight[b] + 0.5 * (weight[(b + 1) % bins] + weight[(b - 1 + bins) % bins]),
  );
  int best = 0;
  for (int b = 1; b < bins; b++) {
    if (smooth[b] > smooth[best]) best = b;
  }
  final colourful = colourfulPx > n * 0.06;

  if (!colourful) {
    // Monochrome / desaturated cover: neutral palette with a faint warmth,
    // vibrant becomes a soft white so accents stay quiet but legible.
    final avgV = totalV / n;
    final avgS = totalS / n;
    final deep = _hsl(30, 0.06 + avgS * 0.2, 0.07);
    final base = _hsl(30, 0.05 + avgS * 0.2, (0.16 + avgV * 0.12).clamp(0.16, 0.26));
    return [deep, base, 0xFFEDEDED, _hsl(35, 0.25, 0.70)];
  }

  double hueOf(int b) => weight[b] > 0 ? sumH[b] / weight[b] : b * (360 / bins) + 7.5;
  double satOf(int b) => weight[b] > 0 ? sumS[b] / weight[b] : 0.6;

  // Brand guard: roles are never purple or pink (the cover itself is shown
  // untouched; only the colours derived from it are steered).
  final h1 = AlbumPalette.guardHue(hueOf(best));
  final s1 = satOf(best);

  // Second hue: strongest bin at least 40° away from the first.
  int second = -1;
  for (int b = 0; b < bins; b++) {
    final d = ((hueOf(b) - h1).abs() % 360);
    final dist = math.min(d, 360 - d);
    if (dist < 40 || weight[b] <= 0) continue;
    if (second == -1 || smooth[b] > smooth[second]) second = b;
  }
  final hasSecond = second != -1 && smooth[second] > smooth[best] * 0.18;
  final h2 = AlbumPalette.guardHue(hasSecond ? hueOf(second) : (h1 + 28) % 360);
  final s2 = hasSecond ? satOf(second) : s1;

  final deep = _hsl(h1, AlbumPalette.guardSaturation(h1, (s1 * 0.75).clamp(0.30, 0.75)), 0.085);
  final base = _hsl(h1, AlbumPalette.guardSaturation(h1, (s1 * 0.85).clamp(0.38, 0.80)), 0.24);

  // Vibrant: saturated and bright enough for ≥4.5:1 on the deep ground.
  double l = 0.56;
  int vibrant = _hsl(h1, (s1 * 1.2).clamp(0.62, 0.95), l);
  while (_contrast(vibrant, deep) < 4.5 && l < 0.86) {
    l += 0.03;
    vibrant = _hsl(h1, (s1 * 1.2).clamp(0.62, 0.95), l);
  }
  final glow = _hsl(h2, (s2 * 1.1).clamp(0.55, 0.95), 0.62);
  return [deep, base, vibrant, glow];
}

const List<int> _fallbackInts = [0xFF050B07, 0xFF15261B, 0xFF30D158, 0xFF1F3326];

AlbumPalette albumPaletteFromInts(List<int> c) => AlbumPalette(
      deep: Color(c[0]),
      base: Color(c[1]),
      vibrant: Color(c[2]),
      glow: Color(c[3]),
    );
