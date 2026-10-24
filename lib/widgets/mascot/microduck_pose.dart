import '../../core/hive_boxes.dart';
import 'microduck_mesh.dart';

/// What Microduck is doing. Pure data: the painter draws it, the widget
/// animates it, [resolveMicroduckPose] picks it.
enum MicroduckPose {
  /// Standing, breathing, looking about, LED blinking.
  idle,

  /// Walking along.
  walk,

  /// Running along.
  run,

  /// Sitting down, looking about (paused on the mini player's edge).
  sit,

  /// Slumped, LED dim, with drifting z's.
  sleep,

  /// A routine of nine moves locked to the beat.
  dance;

  /// Frames per second worth painting; quiet poses repaint far less often.
  int get fps => switch (this) {
        idle => 30,
        sit => 24,
        sleep => 20,
        walk => 60,
        run => 60,
        dance => 60,
      };
}

/// Tempo the robot dances to when the song's is unknown.
const int defaultDanceBpm = 100;

/// How big the dance moves are: faster songs move more (no loudness or
/// energy tag exists on [Song], so tempo stands in for it).
double danceEnergy(int bpm) => (0.7 + (bpm - 70) / 80 * 0.55).clamp(0.7, 1.25);

const String defaultMicroduckName = 'Microduck';
const int maxMicroduckNameLength = 24;

/// A usable mascot name: trimmed, capped, and never empty.
String cleanMicroduckName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return defaultMicroduckName;
  return t.length > maxMicroduckNameLength ? t.substring(0, maxMicroduckNameLength) : t;
}

/// The saved skin for [name], white when unset or unknown.
MicroduckSkin cleanMicroduckSkin(String? name) =>
    MicroduckSkin.values.firstWhere((s) => s.name == name, orElse: () => MicroduckSkin.white);

/// Midnight to 05:00 local time, when the duck sleeps.
bool isMicroduckNight(DateTime now) => now.hour < 5;

/// A believable tempo from a measured [bpm], or null when unknown.
int? danceBpm(num? bpm) {
  if (bpm == null || bpm < 40 || bpm > 260) return null;
  return bpm.round();
}

/// Seconds between the beats the robot steps on. Above 150 bpm it dances in
/// half time (a step every other beat, so 170 bpm does not blur); below 75 it
/// dances in double time (a step on every half beat, so 60 bpm does not drag).
double danceBeatSeconds(int bpm) {
  final beat = 60 / bpm;
  if (bpm > 150) return beat * 2;
  if (bpm < 75) return beat / 2;
  return beat;
}

/// Where in the song's beat grid [positionSeconds] falls: the number of
/// stepping beats since the first beat, which sits at [offsetSeconds].
double danceBeats(double positionSeconds, int bpm, {double offsetSeconds = 0}) =>
    (positionSeconds - offsetSeconds) / danceBeatSeconds(bpm);

/// Remembers a measured tempo for [songId] in the BPM cache, for the robot
/// to dance to (and anything else that wants it). Never throws.
void cacheBpm(String songId, num bpm) {
  final b = danceBpm(bpm);
  if (b == null) return;
  try {
    if (HiveBoxes.audio.get('bpm_$songId') != b) HiveBoxes.audio.put('bpm_$songId', b);
  } catch (_) {}
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
/// * While [playing] the robot dances if [allowDance] (to the song's tempo,
///   or [defaultDanceBpm] when unknown) and walks otherwise. Paused, it
///   stands still.
MicroduckPose resolveMicroduckPose({
  required bool playing,
  required DateTime now,
  bool reducedMotion = false,
  bool sleepsAtNight = true,
  bool allowDance = false,
  bool sitWhenPaused = false,
}) {
  if (sleepsAtNight && isMicroduckNight(now)) return MicroduckPose.sleep;
  if (reducedMotion) return MicroduckPose.idle;
  if (!playing) return sitWhenPaused ? MicroduckPose.sit : MicroduckPose.idle;
  return allowDance ? MicroduckPose.dance : MicroduckPose.walk;
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
