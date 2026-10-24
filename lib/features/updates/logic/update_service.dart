import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../data/update_manifest.dart';
import 'update_files.dart';
import 'update_source.dart';

/// What the phone tells us about the installed app.
class InstalledApp {
  /// The installed base APK on disk (what patches are applied to).
  final String baseApk;

  /// Supported ABIs, best first.
  final List<String> abis;
  final int versionCode;
  const InstalledApp({required this.baseApk, required this.abis, required this.versionCode});
}

/// Thin wrapper over the Kotlin side (UpdateChannel.kt), so tests can fake it.
class UpdateNative {
  static const _ch = MethodChannel('com.navivibe/updates');

  const UpdateNative();

  Future<InstalledApp?> installedApp() async {
    final m = await _ch.invokeMapMethod<String, dynamic>('installedApp');
    if (m == null) return null;
    return InstalledApp(
      baseApk: m['baseApk'] as String,
      abis: (m['abis'] as List).cast<String>(),
      versionCode: (m['versionCode'] as num).toInt(),
    );
  }

  /// Opens the system installer. Returns false when the user must first allow
  /// installs from NaviVibe (the settings page is opened for them).
  Future<bool> install(String apkPath) async => (await _ch.invokeMethod<bool>('install', {'path': apkPath})) ?? false;
}

/// Why an update could not proceed; [message] is shown to the user as is.
class UpdateException implements Exception {
  final String message;
  final bool needsWifi;
  const UpdateException(this.message, {this.needsWifi = false});
  @override
  String toString() => message;
}

class UpdateCheck {
  final UpdateManifest manifest;
  final UpdatePlan? plan; // Android
  final bool windowsAvailable;
  const UpdateCheck(this.manifest, {this.plan, this.windowsAvailable = false});

  bool get available => plan != null || windowsAvailable;
}

typedef Progress = void Function(double fraction, String stage);

/// Checks the release feed, downloads the cheapest route to the newest build
/// (a binary patch against the installed APK when possible, else the full
/// per-ABI APK), verifies every file by SHA-256, and hands it to the installer.
class UpdateService {
  final Dio _dio;
  final UpdateNative _native;
  final Future<Directory> Function() _stagingDir;

  /// Names of the assets of the last GitHub release read (name -> API url).
  Map<String, String> _githubAssets = const {};

  UpdateService({
    Dio? dio,
    UpdateNative native = const UpdateNative(),
    required Future<Directory> Function() stagingDir,
  })  : _dio = dio ?? Dio(),
        _native = native,
        _stagingDir = stagingDir;

  // -------------------------------------------------------------------------
  // Check
  // -------------------------------------------------------------------------

  Future<UpdateCheck> check(UpdateSource source, {required int installedBuild}) async {
    final manifest = await _fetchManifest(source);
    if (Platform.isAndroid) {
      final app = await _native.installedApp();
      String? sha;
      if (app != null) {
        try {
          sha = await sha256OfFile(File(app.baseApk));
        } catch (_) {}
      }
      final plan = planAndroidUpdate(
        manifest,
        installedBuild: installedBuild,
        abis: app?.abis ?? const [],
        installedSha256: sha,
      );
      return UpdateCheck(manifest, plan: plan);
    }
    if (Platform.isWindows) {
      return UpdateCheck(
        manifest,
        windowsAvailable: manifest.windowsSetup != null && manifest.build > installedBuild,
      );
    }
    return UpdateCheck(manifest);
  }

  Future<UpdateManifest> _fetchManifest(UpdateSource source) async {
    try {
      List<int> bytes;
      if (source.isGithub) {
        final r = await _dio.getUri<Map<String, dynamic>>(
          source.latestReleaseApi,
          options: Options(headers: source.apiHeaders, responseType: ResponseType.json),
        );
        final assets = (r.data!['assets'] as List).cast<Map<String, dynamic>>();
        _githubAssets = {for (final a in assets) a['name'] as String: a['url'] as String};
        final api = _githubAssets['latest.json'];
        if (api == null) throw const UpdateException('The latest release has no latest.json.');
        bytes = await _getBytes(Uri.parse(api), {
          'Accept': 'application/octet-stream',
          if (source.token != null) 'Authorization': 'Bearer ${source.token}',
        });
      } else {
        bytes = await _getBytes(source.manifestUrl!, {
          if (source.token != null) 'Authorization': 'Bearer ${source.token}',
        });
      }
      return UpdateManifest.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    } on UpdateException {
      rethrow;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 404) {
        throw UpdateException(source.token == null
            ? 'Couldn’t read the update feed. If the repository is private, add an access token.'
            : 'Couldn’t read the update feed. Check the address and that the token can read the repository.');
      }
      throw const UpdateException('Couldn’t reach the update server. Check your connection.');
    } on FormatException {
      throw const UpdateException('The update feed isn’t valid.');
    }
  }

  Future<List<int>> _getBytes(Uri url, Map<String, String> headers) async {
    final r = await _open(url, headers);
    final out = BytesBuilder(copy: false);
    await for (final c in r.data!.stream) {
      out.add(c);
    }
    return out.takeBytes();
  }

  // -------------------------------------------------------------------------
  // Download
  // -------------------------------------------------------------------------

  /// GET with redirects followed by hand, so the Authorization header is not
  /// forwarded to another host (GitHub redirects asset downloads to storage
  /// that rejects it).
  Future<Response<ResponseBody>> _open(Uri url, Map<String, String> headers, {int from = 0}) async {
    var u = url;
    var h = Map<String, String>.of(headers);
    for (var hop = 0; hop < 6; hop++) {
      final r = await _dio.getUri<ResponseBody>(
        u,
        options: Options(
          headers: {...h, if (from > 0) 'Range': 'bytes=$from-'},
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final code = r.statusCode ?? 0;
      if (code >= 300 && code < 400) {
        final loc = r.headers.value('location');
        if (loc == null) break;
        final next = u.resolve(loc);
        if (next.host != u.host) h = {for (final e in h.entries) if (e.key != 'Authorization') e.key: e.value};
        u = next;
        continue;
      }
      return r;
    }
    throw const UpdateException('Too many redirects from the update server.');
  }

  /// Downloads [file] to [dest], resuming a partial `.part` file, and checks
  /// its SHA-256. A bad file is deleted so the next attempt starts clean.
  Future<File> download(
    DownloadTarget target,
    UpdateFile file,
    File dest, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    if (dest.existsSync() && await sha256OfFile(dest) == file.sha256) return dest;
    final part = File('${dest.path}.part');
    await part.parent.create(recursive: true);
    var have = part.existsSync() ? part.lengthSync() : 0;
    if (have > file.size) {
      await part.delete();
      have = 0;
    }
    if (have < file.size) {
      final r = await _open(target.url, target.headers, from: have);
      if (r.statusCode != 206) have = 0; // server ignored Range: start over
      final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
      var got = have;
      try {
        await for (final chunk in r.data!.stream) {
          if (cancel?.isCancelled ?? false) throw const UpdateException('Cancelled.');
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, file.size);
        }
      } finally {
        await sink.close();
      }
    }
    if (part.lengthSync() != file.size || await sha256OfFile(part) != file.sha256) {
      await part.delete();
      throw UpdateException('${file.name} arrived damaged. Try again.');
    }
    if (dest.existsSync()) await dest.delete();
    return part.rename(dest.path);
  }

  // -------------------------------------------------------------------------
  // Fetch the new APK
  // -------------------------------------------------------------------------

  /// Produces the verified new APK for [plan]: via a patch when there is one,
  /// falling back to the full APK if the patch cannot be used for any reason.
  Future<File> prepareApk(
    UpdatePlan plan,
    UpdateSource source, {
    required bool wifiOnly,
    required Future<bool> Function() onWifi,
    Progress? progress,
    CancelToken? cancel,
  }) async {
    if (wifiOnly && !await onWifi()) {
      throw const UpdateException('Waiting for Wi-Fi. Connect, or allow mobile data for this download.', needsWifi: true);
    }
    final dir = await _stagingDir();
    await dir.create(recursive: true);
    final target = File('${dir.path}/NaviVibe-${plan.manifest.build}.apk');

    final patch = plan.patch;
    if (patch != null) {
      try {
        final app = await _native.installedApp();
        if (app == null) throw const UpdateException('No installed APK to patch.');
        final patchFile = await download(
          source.targetFor(patch, plan.manifest, _githubAssets),
          patch,
          File('${dir.path}/${patch.name}'),
          cancel: cancel,
          onProgress: (r, t) => progress?.call(r / t * 0.8, 'Downloading update'),
        );
        progress?.call(0.85, 'Applying update');
        final out = '${target.path}.tmp';
        final sha = await applyPatchFiles(oldPath: app.baseApk, patchPath: patchFile.path, outPath: out);
        await patchFile.delete();
        if (sha != plan.full.sha256) {
          await File(out).delete();
          throw const UpdateException('Patched file did not verify.');
        }
        if (target.existsSync()) await target.delete();
        await File(out).rename(target.path);
        progress?.call(1, 'Ready to install');
        return target;
      } on UpdateException catch (e) {
        if (e.needsWifi || (cancel?.isCancelled ?? false)) rethrow;
      } catch (_) {
        // Patch failed in any other way: use the full APK below.
      }
    }

    final full = await download(
      source.targetFor(plan.full, plan.manifest, _githubAssets),
      plan.full,
      target,
      cancel: cancel,
      onProgress: (r, t) => progress?.call(r / t, 'Downloading update'),
    );
    progress?.call(1, 'Ready to install');
    return full;
  }

  /// Opens the system installer for [apk]. False means the user still has to
  /// allow installs from NaviVibe.
  Future<bool> install(File apk) => _native.install(apk.path);

  /// Removes anything left in the staging folder.
  Future<void> cleanStaging() async {
    try {
      final d = await _stagingDir();
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Windows
  // -------------------------------------------------------------------------

  /// Downloads the Velopack Setup.exe of the newest build and starts it. Setup
  /// replaces the installed copy in place and keeps the user's data.
  Future<void> installWindows(
    UpdateManifest m,
    UpdateSource source, {
    Progress? progress,
    CancelToken? cancel,
  }) async {
    final setup = m.windowsSetup;
    if (setup == null) throw const UpdateException('This release has no Windows installer.');
    final dir = await _stagingDir();
    await dir.create(recursive: true);
    final exe = await download(
      source.targetFor(setup, m, _githubAssets),
      setup,
      File('${dir.path}/${setup.name}'),
      cancel: cancel,
      onProgress: (r, t) => progress?.call(r / t, 'Downloading update'),
    );
    await Process.start(exe.path, const [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
