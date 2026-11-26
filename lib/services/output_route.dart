/// Where this device's sound is going (phone speaker, wired, Bluetooth, car).
///
/// The naming rules are pure Dart so they are unit-tested; the platform
/// (AudioRoute.kt) only reports outputs and says when they change. Event
/// driven: nothing runs while the route is steady.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/platform_utils.dart';
import 'android_integration.dart';

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

@immutable
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

/// The route for [devices]: on Android 13+ these are the outputs media is
/// routed to right now; older versions list everything connected, so the order
/// here is the one Android itself prefers (car, Bluetooth, USB, wired, HDMI),
/// else the phone speaker.
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
  // A wired plug has no name of its own: Android reports the phone's model.
  if (first({AudioDevice.wiredHeadset, AudioDevice.wiredHeadphones}) != null) {
    return const OutputRoute(RouteKind.wired, 'Wired headphones');
  }
  if (first({AudioDevice.hdmi}) != null) return const OutputRoute(RouteKind.hdmi, 'HDMI');
  return OutputRoute.speaker;
}

/// The current route, or null where the platform doesn't tell (everything but
/// Android). Refreshes when Android reports a change and when the app comes
/// back (the system's output switcher can move sound without any device being
/// added or removed).
class OutputRouteNotifier extends Notifier<OutputRoute?> {
  @override
  OutputRoute? build() {
    if (!PlatformUtils.isAndroid) return null;
    AndroidIntegration.onAudioRouteChanged = refresh;
    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      AndroidIntegration.onAudioRouteChanged = null;
      lifecycle.dispose();
    });
    refresh();
    return null;
  }

  Future<void> refresh() async {
    final devices = await AndroidIntegration.audioOutputs();
    // An empty list means the platform couldn't say; don't claim the speaker.
    if (!ref.mounted || devices.isEmpty) return;
    final route = outputRoute(devices);
    if (route != state) state = route;
  }
}

final outputRouteProvider = NotifierProvider<OutputRouteNotifier, OutputRoute?>(OutputRouteNotifier.new);
