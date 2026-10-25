import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/hive_boxes.dart';
import 'update_service.dart';
import 'update_source.dart';

/// The build number this binary was made from. CI bakes it in with
/// `--dart-define=NAVI_BUILD=<n>`; otherwise it is read back from the package,
/// undoing the ABI offset Flutter adds to split APKs (abi * 1000 + build).
int installedBuildNumber(String packageBuild) {
  const baked = int.fromEnvironment('NAVI_BUILD');
  if (baked > 0) return baked;
  final n = int.tryParse(packageBuild) ?? 0;
  return Platform.isAndroid ? n % 1000 : n;
}

/// Whether this build can update itself at all.
bool get updatesSupported => Platform.isAndroid || Platform.isWindows;

class UpdateSettings {
  final String source;
  final String token;
  final bool wifiOnly;
  final bool beta;
  const UpdateSettings({this.source = '', this.token = '', this.wifiOnly = true, this.beta = false});

  UpdateSource? get parsed => UpdateSource.parse(source, token: token, beta: beta);
  bool get enabled => parsed != null;
}

class UpdateSettingsNotifier extends Notifier<UpdateSettings> {
  @override
  UpdateSettings build() {
    String str(Object? v) => v is String ? v : '';
    return UpdateSettings(
      source: str(HiveBoxes.prefs.get(HiveBoxes.kUpdateSource)),
      token: str(HiveBoxes.auth.get(HiveBoxes.kUpdateToken)),
      wifiOnly: HiveBoxes.prefs.get(HiveBoxes.kUpdateWifiOnly) != false,
      beta: HiveBoxes.prefs.get(HiveBoxes.kUpdateBeta) == true,
    );
  }

  Future<void> setSource(String v) async {
    await HiveBoxes.prefs.put(HiveBoxes.kUpdateSource, v.trim());
    state = UpdateSettings(source: v.trim(), token: state.token, wifiOnly: state.wifiOnly, beta: state.beta);
    ref.invalidate(updateCheckProvider);
  }

  Future<void> setToken(String v) async {
    await HiveBoxes.auth.put(HiveBoxes.kUpdateToken, v.trim());
    state = UpdateSettings(source: state.source, token: v.trim(), wifiOnly: state.wifiOnly, beta: state.beta);
    ref.invalidate(updateCheckProvider);
  }

  Future<void> setWifiOnly(bool v) async {
    await HiveBoxes.prefs.put(HiveBoxes.kUpdateWifiOnly, v);
    state = UpdateSettings(source: state.source, token: state.token, wifiOnly: v, beta: state.beta);
  }

  Future<void> setBeta(bool v) async {
    await HiveBoxes.prefs.put(HiveBoxes.kUpdateBeta, v);
    state = UpdateSettings(source: state.source, token: state.token, wifiOnly: state.wifiOnly, beta: v);
    ref.invalidate(updateCheckProvider);
  }
}

final updateSettingsProvider = NotifierProvider<UpdateSettingsNotifier, UpdateSettings>(UpdateSettingsNotifier.new);

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60))),
    stagingDir: () async => Directory('${(await getTemporaryDirectory()).path}/updates'),
  );
});

Future<bool> onWifiOrEthernet() async {
  final r = await Connectivity().checkConnectivity();
  return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
}

/// One check per launch (and again when the source changes or the user taps
/// Check Again). Null when updates are off or unsupported here. A failed
/// check is an error state the Updates screen shows; the Home banner ignores it.
final updateCheckProvider = FutureProvider<UpdateCheck?>((ref) async {
  if (!updatesSupported) return null;
  final source = ref.watch(updateSettingsProvider).parsed;
  if (source == null) return null;
  final info = await PackageInfo.fromPlatform();
  return ref.read(updateServiceProvider).check(source, installedBuild: installedBuildNumber(info.buildNumber));
});

/// Build number the user dismissed the Home banner for.
class DismissedUpdateNotifier extends Notifier<int> {
  @override
  int build() {
    final v = HiveBoxes.prefs.get(HiveBoxes.kUpdateDismissed);
    return v is int ? v : 0;
  }

  Future<void> dismiss(int build) async {
    state = build;
    await HiveBoxes.prefs.put(HiveBoxes.kUpdateDismissed, build);
  }
}

final dismissedUpdateProvider = NotifierProvider<DismissedUpdateNotifier, int>(DismissedUpdateNotifier.new);

/// Progress of the running download, shared by the Updates screen and Home.
class UpdateRun {
  final bool busy;
  final double fraction;
  final String stage;
  final String? error;
  final bool needsWifi;
  final bool installReady;
  const UpdateRun({
    this.busy = false,
    this.fraction = 0,
    this.stage = '',
    this.error,
    this.needsWifi = false,
    this.installReady = false,
  });
}

class UpdateRunNotifier extends Notifier<UpdateRun> {
  CancelToken? _cancel;
  File? _apk;

  @override
  UpdateRun build() => const UpdateRun();

  Future<void> start(UpdateCheck check, {bool ignoreWifiRule = false}) async {
    final source = ref.read(updateSettingsProvider).parsed;
    if (source == null || state.busy) return;
    final service = ref.read(updateServiceProvider);
    _cancel = CancelToken();
    state = const UpdateRun(busy: true, stage: 'Starting');
    try {
      void progress(double f, String s) => state = UpdateRun(busy: true, fraction: f, stage: s);
      if (Platform.isWindows) {
        await service.installWindows(check.manifest, source, progress: progress, cancel: _cancel);
        return;
      }
      _apk = await service.prepareApk(
        check.plan!,
        source,
        wifiOnly: ref.read(updateSettingsProvider).wifiOnly && !ignoreWifiRule,
        onWifi: onWifiOrEthernet,
        progress: progress,
        cancel: _cancel,
      );
      state = const UpdateRun(fraction: 1, stage: 'Ready to install', installReady: true);
      await install();
    } on UpdateException catch (e) {
      state = UpdateRun(error: e.message, needsWifi: e.needsWifi);
    } on DioException catch (e) {
      state = UpdateRun(
        error: e.type == DioExceptionType.cancel ? null : 'The download was interrupted. Try again to resume.',
      );
    } catch (_) {
      state = const UpdateRun(error: 'The update failed. Try again.');
    }
  }

  /// Opens the system installer for the verified APK.
  Future<void> install() async {
    final apk = _apk;
    if (apk == null) return;
    final ok = await ref.read(updateServiceProvider).install(apk);
    state = ok
        ? const UpdateRun(fraction: 1, stage: 'Ready to install', installReady: true)
        : const UpdateRun(
            fraction: 1,
            stage: 'Allow installs from NaviVibe, then tap Install again',
            installReady: true,
          );
  }

  void cancel() => _cancel?.cancel();
}

final updateRunProvider = NotifierProvider<UpdateRunNotifier, UpdateRun>(UpdateRunNotifier.new);
