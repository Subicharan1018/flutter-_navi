// =============================================================================
// session_sync_provider.dart — Riverpod providers for SessionSyncService
//
// Exposes the singleton SessionSyncService and its reactive streams to the app.
// Note: Intentionally non-autoDispose so socket connectivity persists across
// screen navigation (e.g. NowPlaying, Library, Settings).
//
// Connecting: the service connects as soon as there are credentials, drops
// the socket on sign-out, and reconnects at once when the app comes back to the
// foreground (a phone that slept lost its socket without being told).
// =============================================================================

import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/session_sync_service.dart';
import '../utils/platform_utils.dart';
import 'settings_provider.dart';

/// A readable name for this device in the "Playing on" list, unless the person
/// set their own (`sync_device_name` in prefs).
String defaultSyncDeviceName() {
  try {
    final custom = HiveBoxes.prefs.get('sync_device_name')?.toString().trim() ?? '';
    if (custom.isNotEmpty) return custom;
  } catch (_) {}
  if (PlatformUtils.isTv) return 'Android TV';
  if (PlatformUtils.isAndroid) return 'Android phone';
  if (PlatformUtils.isMobile) return 'iPhone';
  if (PlatformUtils.isWindows) return 'Windows PC';
  if (PlatformUtils.isMacOS) return 'Mac';
  if (PlatformUtils.isLinux) return 'Linux PC';
  return 'This device';
}

/// What this device calls itself in the list: the model on a phone, the
/// computer name on a PC, "Android TV (model)" on a TV. Falls back to the
/// generic name if the platform won't say.
Future<String> loadSyncDeviceName() async {
  try {
    final custom = HiveBoxes.prefs.get('sync_device_name')?.toString().trim() ?? '';
    if (custom.isNotEmpty) return custom;
  } catch (_) {}
  try {
    final info = DeviceInfoPlugin();
    if (PlatformUtils.isAndroid) {
      final a = await info.androidInfo;
      final maker = a.manufacturer.trim();
      final model = a.model.trim();
      final full = model.toLowerCase().startsWith(maker.toLowerCase()) || maker.isEmpty
          ? model
          : '${maker[0].toUpperCase()}${maker.substring(1)} $model';
      return PlatformUtils.isTv ? 'Android TV ($model)' : full;
    }
    if (PlatformUtils.isWindows) return 'Windows PC (${(await info.windowsInfo).computerName})';
    if (PlatformUtils.isMacOS) return 'Mac (${(await info.macOsInfo).computerName})';
    if (PlatformUtils.isLinux) return 'Linux PC (${(await info.linuxInfo).name})';
  } catch (_) {}
  return defaultSyncDeviceName();
}

SyncDeviceType defaultSyncDeviceType() {
  if (PlatformUtils.isTv) return SyncDeviceType.tv;
  if (PlatformUtils.isMobile) return SyncDeviceType.phone;
  if (PlatformUtils.isDesktop) return SyncDeviceType.desktop;
  return SyncDeviceType.unknown;
}

/// Central singleton provider for SessionSyncService.
///
/// Reads credentials from settingsProvider on demand and automatically disposes
/// when the ProviderContainer is destroyed.
final sessionSyncServiceProvider = Provider<SessionSyncService>((ref) {
  final service = SessionSyncService(
    deviceNameProvider: loadSyncDeviceName,
    deviceType: defaultSyncDeviceType(),
    jwtSupplier: ({bool forceRefresh = false}) {
      final settings = ref.read(settingsProvider);
      if (settings.username.isNotEmpty && settings.password.isNotEmpty) {
        return base64Encode(
          utf8.encode('${settings.username}:${settings.password}'),
        );
      }
      return null;
    },
  );

  bool hasCredentials() {
    final s = ref.read(settingsProvider);
    return s.username.isNotEmpty && s.password.isNotEmpty;
  }

  if (hasCredentials()) service.connect().ignore();

  // Signing in, out, or switching account.
  ref.listen(settingsProvider.select((s) => (s.username, s.password)), (prev, next) {
    if (prev == next) return;
    // A different account: nothing of the old one (token, socket, devices) may carry over.
    service.resetAccount();
    if (next.$1.isNotEmpty && next.$2.isNotEmpty) service.connect().ignore();
  });

  final lifecycle = AppLifecycleListener(onResume: () {
    if (hasCredentials() && service.connection != SyncConnection.online) service.connect().ignore();
  });

  ref.onDispose(lifecycle.dispose);
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in account's playback state as the server holds it.
final syncPlaybackProvider = StreamProvider<PlaybackState>((ref) async* {
  final service = ref.watch(sessionSyncServiceProvider);
  yield service.currentState;
  yield* service.stateStream;
});

/// This account's connected devices, active one flagged.
final syncDevicesProvider = StreamProvider<List<SyncDevice>>((ref) async* {
  final service = ref.watch(sessionSyncServiceProvider);
  yield service.currentDevices;
  yield* service.devicesStream;
});

/// Whether the live link is up, coming up or down.
final syncConnectionProvider = StreamProvider<SyncConnection>((ref) async* {
  final service = ref.watch(sessionSyncServiceProvider);
  yield service.connection;
  yield* service.connectionStream;
});
