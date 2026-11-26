/// The Windows / Linux equalizer: one FFmpeg peaking filter per band, run by
/// mpv. Pure maths, unit tested.
library;

import 'dart:math' as math;

import 'eq_model.dart';

/// Bandwidth of each peaking filter, in octaves: about the distance to the
/// neighbouring bands, so the six overlap into a smooth curve.
const List<double> kPeakWidthOctaves = [1.4, 1.4, 1.4, 1.35, 1.6, 2.2];

const double _sampleRate = 48000;

/// Response in dB at [hz] of one peaking biquad (RBJ cookbook, bandwidth in
/// octaves: the same formula FFmpeg's `equalizer=t=o` uses).
double peakingResponseDb({required double hz, required double centreHz, required double widthOctaves, required double gainDb}) {
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * centreHz / _sampleRate;
  final sinW0 = math.sin(w0), cosW0 = math.cos(w0);
  final x = math.ln2 / 2 * widthOctaves * w0 / sinW0;
  final alpha = sinW0 * (math.exp(x) - math.exp(-x)) / 2;
  final b0 = 1 + alpha * a, b1 = -2 * cosW0, b2 = 1 - alpha * a;
  final a0 = 1 + alpha / a, a1 = -2 * cosW0, a2 = 1 - alpha / a;
  final w = 2 * math.pi * hz / _sampleRate;
  double power(double c0, double c1, double c2) {
    final re = c0 + c1 * math.cos(w) + c2 * math.cos(2 * w);
    final im = c1 * math.sin(w) + c2 * math.sin(2 * w);
    return re * re + im * im;
  }

  return 10 * math.log(power(b0, b1, b2) / power(a0, a1, a2)) / math.ln10;
}

double bankResponseDb(List<double> filterGains, double hz) {
  var sum = 0.0;
  for (var i = 0; i < kEqFrequencies.length; i++) {
    sum += peakingResponseDb(
      hz: hz,
      centreHz: kEqFrequencies[i],
      widthOctaves: kPeakWidthOctaves[i],
      gainDb: filterGains[i],
    );
  }
  return sum;
}

/// Overlapping filters add up, so each is given the gain that makes the whole
/// bank hit [target] at the six band frequencies.
List<double> solveFilterGains(List<double> target) {
  final g = [...target];
  for (var pass = 0; pass < 40; pass++) {
    for (var i = 0; i < g.length; i++) {
      final error = target[i] - bankResponseDb(g, kEqFrequencies[i]);
      g[i] = (g[i] + error * 0.7).clamp(-24.0, 24.0);
    }
  }
  return g;
}

/// The loudest boost anywhere in the bank (never below 0), for headroom.
double bankPeakDb(List<double> filterGains) {
  var peak = 0.0;
  for (var i = 0; i <= 96; i++) {
    final hz = 20 * math.pow(1000, i / 96).toDouble(); // 20 Hz … 20 kHz
    peak = math.max(peak, bankResponseDb(filterGains, hz));
  }
  return peak;
}

class MpvEq {
  /// Value for mpv's `af` property; empty removes the filter.
  final String filter;

  /// Linear volume factor (≤ 1) that keeps the boosted signal from clipping.
  final double headroom;

  const MpvEq(this.filter, this.headroom);

  static const off = MpvEq('', 1);
}

MpvEq mpvEqFor(List<double> gains) {
  if (isFlat(gains)) return MpvEq.off;
  final solved = solveFilterGains(gains);
  // r=f32 keeps the processing in floating point, so a boost cannot clip
  // before the volume is turned down.
  final parts = [
    for (var i = 0; i < kEqFrequencies.length; i++)
      'equalizer=f=${kEqFrequencies[i].round()}:t=o:w=${kPeakWidthOctaves[i]}'
          ':g=${solved[i].toStringAsFixed(2)}:r=f32',
  ];
  // The leading mpv `format` filter is required: the audio-only libmpv that
  // ships on Windows has no `aresample`, so FFmpeg cannot convert to the
  // planar format `equalizer` needs and mpv silently drops the whole filter.
  return MpvEq(
    'format=format=floatp,lavfi=[${parts.join(',')}]',
    math.pow(10, -bankPeakDb(solved) / 20).toDouble(),
  );
}
