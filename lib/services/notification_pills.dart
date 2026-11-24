/// Pure logic behind the richer Android notifications: where sound is going,
/// progress mapping for Live Updates, update throttling, the media
/// notification's button presets and the wording of the finished notices.
/// No platform calls here, so all of it is unit-tested.
library;

// ── audio output route ───────────────────────────────────────────────────────

/// One output as Android's `AudioDeviceInfo` reports it.
class AudioDevice {
  // AudioDeviceInfo.TYPE_* constants.
  static const earpiece = 1;
  static const builtinSpeaker = 2;
  static const wiredHeadset = 3;
  static const wiredHeadphones = 4;
  static const bluetoothSco = 7;
  static const bluetoothA2dp = 8;
  static const hdmi = 9;
  static const usbDevice = 11;
  static const bus = 21;
  static const usbHeadset = 22;
  static const hearingAid = 23;
  static const bleHeadset = 26;
  static const bleSpeaker = 27;

  final int type;
  final String name;
  const AudioDevice({required this.type, this.name = ''});

  static List<AudioDevice> parseList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final m in raw)
        if (m is Map && m['type'] is int)
          AudioDevice(type: m['type'] as int, name: (m['name'] as String?)?.trim() ?? ''),
    ];
  }
}

enum RouteKind { speaker, wired, bluetooth, usb, hdmi, car }

class OutputRoute {
  final RouteKind kind;
  final String label;
  const OutputRoute(this.kind, this.label);

  static const speaker = OutputRoute(RouteKind.speaker, 'Phone speaker');

  @override
  bool operator ==(Object other) => other is OutputRoute && other.kind == kind && other.label == label;
  @override
  int get hashCode => Object.hash(kind, label);
}

/// Where sound is going: the connected output Android itself would prefer
/// (car, then Bluetooth, then USB, wired, HDMI), else the phone speaker.
OutputRoute outputRoute(List<AudioDevice> devices) {
  AudioDevice? first(Set<int> types) {
    for (final d in devices) {
      if (types.contains(d.type)) return d;
    }
    return null;
  }

  String named(AudioDevice d, String fallback) => d.name.trim().isEmpty ? fallback : d.name.trim();

  final car = first({AudioDevice.bus});
  if (car != null) return OutputRoute(RouteKind.car, named(car, 'Car'));
  final bt = first({
    AudioDevice.bluetoothA2dp,
    AudioDevice.bleHeadset,
    AudioDevice.bleSpeaker,
    AudioDevice.hearingAid,
    AudioDevice.bluetoothSco,
  });
  if (bt != null) return OutputRoute(RouteKind.bluetooth, named(bt, 'Bluetooth headphones'));
  final usb = first({AudioDevice.usbHeadset, AudioDevice.usbDevice});
  if (usb != null) return OutputRoute(RouteKind.usb, named(usb, 'USB audio'));
  if (first({AudioDevice.wiredHeadset, AudioDevice.wiredHeadphones}) != null) {
    return const OutputRoute(RouteKind.wired, 'Wired headphones');
  }
  if (first({AudioDevice.hdmi}) != null) return const OutputRoute(RouteKind.hdmi, 'HDMI');
  return OutputRoute.speaker;
}

/// The media notification's subtext.
String routeSubtext(OutputRoute r) => r.kind == RouteKind.speaker ? r.label : 'Playing on ${r.label}';

// ── progress mapping ─────────────────────────────────────────────────────────

class LiveProgress {
  final int value;
  final int max;
  final bool indeterminate;

  /// Short text for the status-bar chip.
  final String chip;
  const LiveProgress(this.value, this.max, this.indeterminate, this.chip);
}

/// "2 of 8 songs": [done] of [total] jobs.
LiveProgress countedProgress({required int done, required int total}) {
  if (total <= 0) return const LiveProgress(0, 0, true, '');
  final v = done.clamp(0, total);
  return LiveProgress(v, total, false, '$v/$total');
}

/// A 0–1 fraction as percent; null means not measurable yet.
LiveProgress fractionProgress(double? f) {
  if (f == null) return const LiveProgress(0, 0, true, '');
  final v = (f.clamp(0.0, 1.0) * 100).round();
  return LiveProgress(v, 100, false, '$v%');
}

// ── throttling ───────────────────────────────────────────────────────────────

/// Lets an update through when its content changed and [gap] has passed since
/// the last one that went through. `force` (the final update) always passes.
class UpdateGate {
  UpdateGate(this.gap, [DateTime Function()? now]) : _now = now ?? DateTime.now;

  final Duration gap;
  final DateTime Function() _now;
  String? _lastKey;
  DateTime? _lastAt;

  bool allow(String key, {bool force = false}) {
    final now = _now();
    if (!force) {
      if (key == _lastKey) return false;
      final at = _lastAt;
      if (at != null && now.difference(at) < gap) return false;
    }
    _lastKey = key;
    _lastAt = now;
    return true;
  }

  void reset() {
    _lastKey = null;
    _lastAt = null;
  }
}

// ── media notification buttons ───────────────────────────────────────────────

/// Android shows previous, play and next plus at most three custom buttons
/// that fit the expanded media notification; the preset picks which three.
enum ButtonPreset {
  classic('Like, shuffle, repeat', ['like', 'shuffle', 'repeat']),
  seek('Like, back 10 s, forward 30 s', ['like', 'back10', 'forward30']),
  sleep('Like, sleep timer, repeat', ['like', 'sleep', 'repeat']);

  final String label;
  final List<String> extras;
  const ButtonPreset(this.label, this.extras);

  static ButtonPreset parse(Object? raw) => values.firstWhere((p) => p.name == raw, orElse: () => classic);
}

/// Where a skip button lands: inside the song, never past its end.
Duration seekBy(Duration position, int seconds, Duration? length) {
  var t = position + Duration(seconds: seconds);
  if (t < Duration.zero) t = Duration.zero;
  if (length != null && t >= length) t = length - const Duration(seconds: 1);
  if (t < Duration.zero) t = Duration.zero;
  return t;
}

// ── notice wording ───────────────────────────────────────────────────────────

class FetchedNotice {
  final String title;
  final String body;
  final List<String> playIds;
  const FetchedNotice(this.title, this.body, this.playIds);
}

/// "X is in your library", or null when nothing landed.
FetchedNotice? fetchedNotice(List<String> songIds, String name, String artist) {
  if (songIds.isEmpty) return null;
  final detail = songIds.length == 1 ? (artist.isEmpty ? 'Tap to play' : '$artist · tap to play') : '${songIds.length} songs · tap to play';
  return FetchedNotice('$name is in your library', detail, songIds);
}

String jamLine({required String code, required int people}) =>
    '$code · ${people <= 1 ? 'just you' : '$people people'}';

String joinPlayIds(List<String> ids) => ids.join(',');

List<String> parsePlayIds(String? raw) => raw == null ? const [] : [for (final s in raw.split(',')) if (s.isNotEmpty) s];
