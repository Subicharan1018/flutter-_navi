/// One player volume, two owners: the listener's slider and the app's own
/// gain (normalisation, crossfade, equalizer headroom). Each keeps its own
/// value, so neither overwrites the other.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class _Mix {
  double user;
  double gain = 1.0;
  _Mix(this.user);
}

final Expando<_Mix> _mixes = Expando<_Mix>('playerVolumeMix');

/// mpv's volume is cubic: a setting of 0.5 plays at 0.125 of full amplitude
/// (-18 dB). Android, iOS and browsers are linear. [kCubicPlayerVolume] marks
/// the platforms where the app's gain must be cube-rooted first.
final bool kCubicPlayerVolume = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) &&
    !const bool.hasEnvironment('FLUTTER_TEST');

/// The value to hand the player for the slider at [user] and an amplitude
/// factor of [gain].
double effectiveVolume(double user, double gain, {required bool cubic}) {
  final g = gain.clamp(0.0, 1.0).toDouble();
  final scaled = cubic ? math.pow(g, 1 / 3).toDouble() : g;
  return (user * scaled).clamp(0.0, 1.0).toDouble();
}

extension PlayerVolume on AudioPlayer {
  /// Where the volume slider is, whatever gain is applied on top.
  double get userVolume => _mixes[this]?.user ?? volume;

  Stream<double> get userVolumeStream => volumeStream.map((_) => userVolume);

  Future<void> setUserVolume(double v) {
    final m = _mixes[this] ??= _Mix(v);
    m.user = v.clamp(0.0, 1.0).toDouble();
    return setVolume(effectiveVolume(m.user, m.gain, cubic: kCubicPlayerVolume));
  }

  /// [gain] is an amplitude factor, 0–1.
  Future<void> setAppGain(double gain) {
    // Every slider goes through [setUserVolume], so no mix yet means the
    // slider has not moved from full.
    final m = _mixes[this] ??= _Mix(1.0);
    m.gain = gain;
    return setVolume(effectiveVolume(m.user, m.gain, cubic: kCubicPlayerVolume));
  }
}
