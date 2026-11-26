import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// connectivity_plus asks NetworkManager on Linux. Distros without it
/// (systemd-networkd, connman, containers) made every check throw, which
/// failed downloads and logged unhandled errors. There the app assumes it is
/// online; a request that cannot reach the server still reports its own error.
Future<void> installLinuxConnectivityFallback({Duration timeout = const Duration(seconds: 2)}) async {
  try {
    await ConnectivityPlatform.instance.checkConnectivity().timeout(timeout);
  } catch (e) {
    debugPrint('[Connectivity] NetworkManager unavailable ($e); assuming online.');
    ConnectivityPlatform.instance = AssumeOnlineConnectivity();
  }
}

class AssumeOnlineConnectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => const [ConnectivityResult.other];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
