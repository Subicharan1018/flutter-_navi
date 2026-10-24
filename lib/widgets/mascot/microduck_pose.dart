import '../../core/hive_boxes.dart';

/// What Microduck is doing. Pure data: the painter draws it, the widget
/// animates it, [resolveMicroduckPose] picks it.
enum MicroduckPose {
  /// Standing, blinking now and then.
  idle,

  /// Trotting along.
  run,

  /// Tucked in with a slow breath and drifting z's.
  sleep,

  /// Hopping on the beat, with note marks.
  dance;

  /// Frames per second worth painting; quiet poses repaint far less often.
  int get fps => switch (this) {
        idle => 12,
        sleep => 15,
        run => 60,
        dance => 60,
      };
}

const String defaultMicroduckName = 'Microduck';
const int maxMicroduckNameLength = 24;

/// A usable mascot name: trimmed, capped, and never empty.
String cleanMicroduckName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return defaultMicroduckName;
  return t.length > maxMicroduckNameLength ? t.substring(0, maxMicroduckNameLength) : t;
}

/// Midnight to 05:00 local time, when the duck sleeps.
bool isMicroduckNight(DateTime now) => now.hour < 5;

/// Slowest and fastest tempos the duck will hop to; anything outside is
/// folded (half/double time) so a 170 bpm track doesn't blur.
const int _minBpm = 70;
const int _maxBpm = 150;

/// A hop-friendly tempo from a measured [bpm], or null when unknown.
int? danceBpm(num? bpm) {
  if (bpm == null || bpm < 40 || bpm > 260) return null;
  var b = bpm.round();
  while (b > _maxBpm) {
    b = (b / 2).round();
  }
  while (b < _minBpm) {
    b *= 2;
  }
  return b;
}

/// The tempo the BPM cache holds for [songId] (see "Cache Tempo" in
/// Settings), or null when it was never measured.
int? cachedBpm(String songId) {
  try {
    final v = HiveBoxes.audio.get('bpm_$songId');
    return v is num ? danceBpm(v) : null;
  } catch (_) {
    return null;
  }
}

/// Picks the pose.
///
/// * Reduced motion never animates, so it gets a still pose: asleep at night,
///   otherwise standing.
/// * [sleepsAtNight] puts the duck to sleep between 00:00 and 05:00.
/// * While [playing] the duck dances if [bpm] is known and [allowDance], and
///   trots otherwise. Paused, it stands still.
MicroduckPose resolveMicroduckPose({
  required bool playing,
  required DateTime now,
  bool reducedMotion = false,
  bool sleepsAtNight = true,
  bool allowDance = false,
  int? bpm,
}) {
  if (sleepsAtNight && isMicroduckNight(now)) return MicroduckPose.sleep;
  if (reducedMotion || !playing) return MicroduckPose.idle;
  if (allowDance && bpm != null) return MicroduckPose.dance;
  return MicroduckPose.run;
}

/// Empty states show the duck on about a third of the days for each message,
/// so the drawings still appear. Stable within a day so it never flickers.
bool showDuckInEmptyState(String seed, DateTime now) {
  final day = now.difference(DateTime(now.year)).inDays;
  var h = day * 31;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h % 3 == 0;
}
