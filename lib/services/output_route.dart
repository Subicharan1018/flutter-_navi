import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/platform_utils.dart';
import 'android_integration.dart';
import 'notification_pills.dart';

/// Where sound is going right now (phone speaker, headphones, Bluetooth, car).
/// Android only; elsewhere it stays on the speaker. Updates when the system
/// reports a change, never on a timer.
class OutputRouteNotifier extends Notifier<OutputRoute> {
  @override
  OutputRoute build() {
    if (!PlatformUtils.isAndroid) return OutputRoute.speaker;
    AndroidIntegration.onAudioRouteChanged = refresh;
    ref.onDispose(() => AndroidIntegration.onAudioRouteChanged = null);
    refresh();
    return OutputRoute.speaker;
  }

  Future<void> refresh() async {
    final route = outputRoute(await AndroidIntegration.audioOutputs());
    if (ref.mounted && route != state) state = route;
  }
}

final outputRouteProvider = NotifierProvider<OutputRouteNotifier, OutputRoute>(OutputRouteNotifier.new);
