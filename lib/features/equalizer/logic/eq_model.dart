/// Pure equalizer maths and presets: no Flutter, no platform, unit tested.
library;

import 'dart:math' as math;

/// The six bands on the curve, in Hz.
const List<double> kEqFrequencies = [60, 150, 400, 1000, 2400, 15000];
const List<String> kEqFrequencyLabels = ['60Hz', '150Hz', '400Hz', '1KHz', '2.4KHz', '15KHz'];
const double kEqMaxDb = 12;

List<double> flatGains() => List<double>.filled(kEqFrequencies.length, 0);

/// Six gains, clamped and rounded to 0.1 dB. Anything that is not a list of
/// six finite numbers (an old or damaged preference) becomes flat.
List<double> sanitizeGains(Object? raw) {
  if (raw is! List || raw.length != kEqFrequencies.length) return flatGains();
  final out = <double>[];
  for (final v in raw) {
    if (v is! num || !v.isFinite) return flatGains();
    out.add((v.toDouble().clamp(-kEqMaxDb, kEqMaxDb) * 10).round() / 10);
  }
  return out;
}

bool isFlat(List<double> gains) => gains.every((g) => g.abs() < 0.05);

bool sameGains(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() >= 0.05) return false;
  }
  return true;
}

class EqPreset {
  final String name;
  final List<double> gains;
  const EqPreset(this.name, this.gains);
}

const List<EqPreset> kBuiltInPresets = [
  EqPreset('Flat', [0, 0, 0, 0, 0, 0]),
  EqPreset('Bass boost', [6, 4.5, 1.5, 0, 0, 0]),
  EqPreset('Bass reducer', [-6, -4.5, -1.5, 0, 0, 0]),
  EqPreset('Treble boost', [0, 0, 0, 1.5, 3.5, 6]),
  EqPreset('Treble reducer', [0, 0, 0, -1.5, -3.5, -6]),
  EqPreset('Vocal boost', [-2, -1.5, 1.5, 4, 3, 0]),
  EqPreset('Acoustic', [3.5, 2.5, 1, 1.5, 2.5, 3]),
  EqPreset('Rock', [4.5, 3, -1, -0.5, 2, 4]),
  EqPreset('Pop', [-1, 1, 3.5, 3, 1, -1]),
  EqPreset('Classical', [3.5, 2, -0.5, -0.5, 1, 3]),
  EqPreset('Electronic', [4.5, 3.5, 0, -1, 2, 4.5]),
  EqPreset('Hip-hop', [5, 4, 0.5, -0.5, 1, 2.5]),
];

bool isBuiltInPresetName(String name) =>
    kBuiltInPresets.any((p) => p.name.toLowerCase() == name.trim().toLowerCase());

/// The preset whose gains match [gains]; [prefer] wins a tie so the name the
/// listener picked stays shown.
EqPreset? matchingPreset(List<double> gains, List<EqPreset> custom, {String? prefer}) {
  final all = [...custom, ...kBuiltInPresets];
  for (final p in all) {
    if (p.name == prefer && sameGains(p.gains, gains)) return p;
  }
  for (final p in all) {
    if (sameGains(p.gains, gains)) return p;
  }
  return null;
}

/// Slopes for a monotone cubic (Fritsch–Carlson) through points at [x]: the
/// curve never overshoots a band, so it cannot boost more than was asked.
List<double> _monotoneSlopes(List<double> x, List<double> y) {
  final n = x.length;
  final d = [for (var i = 0; i < n - 1; i++) (y[i + 1] - y[i]) / (x[i + 1] - x[i])];
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i], b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  return m;
}

/// The smooth curve through the points ([x], [y]) at [at]; flat past the ends.
double curveAt(List<double> x, List<double> y, double at) {
  if (at <= x.first) return y.first;
  if (at >= x.last) return y.last;
  final m = _monotoneSlopes(x, y);
  var i = 0;
  while (at > x[i + 1]) {
    i++;
  }
  final h = x[i + 1] - x[i];
  final t = (at - x[i]) / h;
  final t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * y[i] +
      (t3 - 2 * t2 + t) * h * m[i] +
      (-2 * t3 + 3 * t2) * y[i + 1] +
      (t3 - t2) * h * m[i + 1];
}

/// Gain in dB at [hz] for the six band [gains], smooth on a log frequency axis.
double gainAtHz(List<double> gains, double hz) =>
    curveAt([for (final f in kEqFrequencies) math.log(f)], gains, math.log(hz));

/// One band of the Android DynamicsProcessing pre-EQ: everything above the
/// previous band's [cutoffHz] up to this one gets [gainDb].
class EqSlice {
  final double cutoffHz;
  final double gainDb;
  const EqSlice(this.cutoffHz, this.gainDb);
}

const int kEqSliceCount = 32;
const double _sliceLowHz = 40;
const double _sliceHighHz = 20000;

/// The curve cut into [count] log-spaced steps, fine enough that what plays
/// follows what is drawn.
List<EqSlice> eqSlices(List<double> gains, {int count = kEqSliceCount}) {
  final ratio = math.pow(_sliceHighHz / _sliceLowHz, 1 / (count - 1)).toDouble();
  return [
    for (var i = 0; i < count; i++)
      EqSlice(
        _sliceLowHz * math.pow(ratio, i).toDouble(),
        gainAtHz(gains, _sliceLowHz * math.pow(ratio, i - 0.5).toDouble()),
      ),
  ];
}

/// How far the whole signal is turned down so the biggest boost cannot clip.
/// Zero when nothing is boosted.
double headroomDb(Iterable<double> gains) => -gains.fold<double>(0, math.max);
