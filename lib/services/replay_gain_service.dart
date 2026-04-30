import 'dart:math';
import '../core/hive_boxes.dart';

enum ReplayGainMode {
  off,
  track,
  album,
}

class ReplayGainService {
  static final ReplayGainService _instance = ReplayGainService._internal();
  factory ReplayGainService() => _instance;
  ReplayGainService._internal();

  /// No-op — Hive boxes are already open from main(). Kept for API compat.
  Future<void> initialize() async {}

  ReplayGainMode getMode() {
    final modeIndexVal = HiveBoxes.audio.get(HiveBoxes.kReplayGainMode, defaultValue: 0);
    final modeIndex = modeIndexVal is int ? modeIndexVal : 0;
    return ReplayGainMode.values[modeIndex.clamp(
      0,
      ReplayGainMode.values.length - 1,
    )];
  }

  Future<void> setMode(ReplayGainMode mode) async {
    await HiveBoxes.audio.put(HiveBoxes.kReplayGainMode, mode.index);
  }

  double getPreampGain() {
    final val = HiveBoxes.audio.get(HiveBoxes.kPreampGain, defaultValue: 0.0);
    return val is double ? val : (val is num ? val.toDouble() : 0.0);
  }

  Future<void> setPreampGain(double gain) async {
    await HiveBoxes.audio.put(HiveBoxes.kPreampGain, gain.clamp(-15.0, 15.0));
  }

  bool getPreventClipping() {
    final val = HiveBoxes.audio.get(HiveBoxes.kPreventClipping, defaultValue: true);
    return val is bool ? val : true;
  }

  Future<void> setPreventClipping(bool prevent) async {
    await HiveBoxes.audio.put(HiveBoxes.kPreventClipping, prevent);
  }

  double getFallbackGain() {
    final val = HiveBoxes.audio.get(HiveBoxes.kFallbackGain, defaultValue: -6.0);
    return val is double ? val : (val is num ? val.toDouble() : -6.0);
  }

  Future<void> setFallbackGain(double gain) async {
    await HiveBoxes.audio.put(HiveBoxes.kFallbackGain, gain.clamp(-15.0, 0.0));
  }

  double calculateVolumeMultiplier({
    double? trackGain,
    double? albumGain,
    double? trackPeak,
    double? albumPeak,
  }) {
    final mode = getMode();

    if (mode == ReplayGainMode.off) {
      return 1.0;
    }

    double? gainDb;
    double? peak;

    if (mode == ReplayGainMode.album && albumGain != null) {
      gainDb = albumGain;
      peak = albumPeak;
    } else if (trackGain != null) {
      gainDb = trackGain;
      peak = trackPeak;
    }

    if (gainDb == null) {
      gainDb = getFallbackGain();
      peak = null;
    }

    final preamp = getPreampGain();
    final totalGainDb = gainDb + preamp;

    double multiplier = pow(10, totalGainDb / 20).toDouble();

    if (getPreventClipping() && peak != null && peak > 0) {
      final maxMultiplier = 1.0 / peak;
      multiplier = min(multiplier, maxMultiplier);
    }

    return multiplier.clamp(0.0, 1.0);
  }

  String getModeDescription() {
    switch (getMode()) {
      case ReplayGainMode.off:
        return 'Off';
      case ReplayGainMode.track:
        return 'Track';
      case ReplayGainMode.album:
        return 'Album';
    }
  }
}
