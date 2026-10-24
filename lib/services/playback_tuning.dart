import 'dart:math' as math;

import '../models/song.dart';

/// Pure maths for ReplayGain, crossfade and playback speed. Kept free of
/// player and Flutter dependencies so it can be unit tested directly.

enum ReplayGainMode { off, track, album }

const double kMinPlaybackSpeed = 0.5;
const double kMaxPlaybackSpeed = 2.0;
const int kMaxCrossfadeSeconds = 12;

double clampPlaybackSpeed(double speed) =>
    speed.clamp(kMinPlaybackSpeed, kMaxPlaybackSpeed).toDouble();

int clampCrossfadeSeconds(int seconds) =>
    seconds.clamp(0, kMaxCrossfadeSeconds);

/// Gain in dB to apply to [song] for [mode], or null when untagged.
/// Album mode falls back to the track gain (and vice versa) so a partly
/// tagged library still gets normalised.
double? replayGainDb(Song song, ReplayGainMode mode) {
  switch (mode) {
    case ReplayGainMode.off:
      return null;
    case ReplayGainMode.track:
      return song.trackGain ?? song.albumGain;
    case ReplayGainMode.album:
      return song.albumGain ?? song.trackGain;
  }
}

/// Linear player volume (0–1) for [song]. The result never exceeds 1.0 —
/// just_audio cannot amplify — and, when the matching peak is known, never
/// exceeds 1 / peak, so a boosted track cannot clip. Untagged songs and
/// [ReplayGainMode.off] play at 1.0.
double replayGainVolume(Song song, ReplayGainMode mode) {
  final db = replayGainDb(song, mode);
  if (db == null || db.isNaN || db.isInfinite) return 1.0;
  var linear = math.pow(10, db / 20).toDouble();
  final peak = (mode == ReplayGainMode.album
          ? (song.albumPeak ?? song.trackPeak)
          : (song.trackPeak ?? song.albumPeak)) ??
      0.0;
  if (peak > 0) linear = math.min(linear, 1 / peak);
  return linear.clamp(0.0, 1.0).toDouble();
}

/// True when [next] follows [current] on the same album in track order, so
/// the pair should stay gapless instead of dipping through a crossfade.
bool isAlbumContinuous(Song current, Song? next) {
  if (next == null) return false;
  if (current.album.isEmpty || current.album != next.album) return false;
  if (current.track <= 0 || next.track <= 0) return false;
  return next.track == current.track + 1;
}

/// Whether the end of [current] should fade out towards [next].
bool shouldCrossfade({
  required int fadeSeconds,
  required Song current,
  required Song? next,
}) {
  if (fadeSeconds <= 0 || next == null) return false;
  if (next.id == current.id) return false;
  return !isAlbumContinuous(current, next);
}

/// Fade multiplier (0–1) for the playback position.
///
/// One player cannot overlap two tracks, so the crossfade is a dip: the
/// last half of [fadeSeconds] ramps the outgoing track down and, when
/// [fadeIn] is set, the first half ramps the incoming track up. Equal-power
/// (sine) curves keep perceived loudness steady through the dip.
double crossfadeGain({
  required int positionMs,
  required int durationMs,
  required int fadeSeconds,
  required bool fadeOut,
  required bool fadeIn,
}) {
  if (fadeSeconds <= 0 || durationMs <= 0) return 1.0;
  final halfMs = fadeSeconds * 500;
  // Never let the two ramps meet inside a track that is shorter than the fade.
  final span = math.min(halfMs, durationMs ~/ 2);
  if (span <= 0) return 1.0;
  var gain = 1.0;
  if (fadeIn && positionMs < span) {
    gain = math.min(gain, _equalPower(positionMs / span));
  }
  final remaining = durationMs - positionMs;
  if (fadeOut && remaining < span) {
    gain = math.min(gain, _equalPower(remaining / span));
  }
  return gain.clamp(0.0, 1.0).toDouble();
}

double _equalPower(double t) => math.sin(t.clamp(0.0, 1.0) * math.pi / 2);
