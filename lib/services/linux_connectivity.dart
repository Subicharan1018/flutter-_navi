import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// connectivity_plus asks NetworkManager on Linux. Distros without it
/// (systemd-networkd, connman, containers) made every check throw, which
/// failed downloads and logged unhandled errors. There the app assumes it is
/// online; a request that cannot reach the server still reports its own error.
Future<void> installLinuxConnectivityFallback({Duration timeout = const Duration(seconds: 2)}) async {
  final answered = Completer<Object?>(); // null: it works; else why not
  void answer(Object? why) {
    if (!answered.isCompleted) answered.complete(why);
  }

  // Its own zone: with no system bus, the NetworkManager client also throws
  // from a signal subscription nobody awaits. A try block misses that one, and
  // it was recorded as a crash.
  runZonedGuarded(() async {
    try {
      await ConnectivityPlatform.instance.checkConnectivity().timeout(timeout);
      answer(null);
    } catch (e) {
      answer(e);
    }
  }, (e, _) => answer(e));

  final why = await answered.future;
  if (why == null) return;
  debugPrint('[Connectivity] NetworkManager unavailable ($why); assuming online.');
  ConnectivityPlatform.instance = AssumeOnlineConnectivity();
}

class AssumeOnlineConnectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => const [ConnectivityResult.other];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
