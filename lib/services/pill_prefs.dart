import '../core/hive_boxes.dart';
import 'notification_pills.dart';

/// Switches for the richer Android notifications. Device-only; a missing or
/// unreadable box (tests, very early start) means the default.
enum Pill {
  /// "Playing on" the device, under the song in the media notification.
  output('pill_output', 'Output device', true),

  /// Download progress as a Live Update.
  downloads('pill_downloads', 'Download progress', true),

  /// Search online fetches as a Live Update.
  fetches('pill_fetches', 'Fetch progress', true),

  /// The sleep timer countdown.
  sleep('pill_sleep', 'Sleep timer countdown', true),

  /// The room code and people in a Jam.
  jam('pill_jam', 'Jam in progress', true),

  /// A "song is in your library" notice; tap to play.
  fetched('pill_fetched', 'Finished fetches', true),

  /// "Weekly Exploration is ready". Once a week at most.
  weekly('pill_weekly', 'Weekly Exploration', true);

  final String key;
  final String label;
  final bool defaultOn;
  const Pill(this.key, this.label, this.defaultOn);

  bool get on {
    try {
      final v = HiveBoxes.prefs.get(key);
      return v is bool ? v : defaultOn;
    } catch (_) {
      return defaultOn;
    }
  }

  Future<void> set(bool v) async {
    try {
      await HiveBoxes.prefs.put(key, v);
    } catch (_) {}
  }
}

const _presetKey = 'pill_buttons';

ButtonPreset get buttonPreset {
  try {
    return ButtonPreset.parse(HiveBoxes.prefs.get(_presetKey));
  } catch (_) {
    return ButtonPreset.classic;
  }
}

Future<void> setButtonPreset(ButtonPreset p) async {
  try {
    await HiveBoxes.prefs.put(_presetKey, p.name);
  } catch (_) {}
}
