import 'dart:async';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../core/hive_boxes.dart';

/// Name of the folder created inside the folder the user picks. Downloads
/// get their own folder so "delete all downloads" can never touch the user's
/// other files.
const downloadsFolderName = 'NaviVibe Downloads';

/// Default location inside the app's documents.
const defaultDownloadsFolderName = 'offline_music';

/// The folder downloads are stored in: the default under the app's documents,
/// or [downloadsFolderName] inside [custom] when the user chose a place.
String resolveOfflineDir({required String appDocs, String? custom}) {
  final base = (custom == null || custom.trim().isEmpty) ? null : custom.trim();
  final sep = Platform.pathSeparator;
  if (base == null) return '$appDocs$sep$defaultDownloadsFolderName';
  final trimmed = base.endsWith(sep) ? base.substring(0, base.length - 1) : base;
  return '$trimmed$sep$downloadsFolderName';
}

/// The chosen parent folder, persisted. Null means "app storage".
class DownloadLocationStore {
  const DownloadLocationStore();

  String? read() {
    try {
      final v = HiveBoxes.prefs.get(HiveBoxes.kDownloadDir);
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String? path) async {
    if (path == null || path.isEmpty) {
      await HiveBoxes.prefs.delete(HiveBoxes.kDownloadDir);
    } else {
      await HiveBoxes.prefs.put(HiveBoxes.kDownloadDir, path);
    }
  }
}

/// Null when [dir] can be created and written to; otherwise a sentence for
/// the user. Android refuses plain-path writes outside the app's own folders
/// on most devices, which is why this is checked before the setting changes.
Future<String?> checkWritable(String dir) async {
  try {
    final d = Directory(dir);
    await d.create(recursive: true);
    final probe = File('${d.path}${Platform.pathSeparator}.navivibe_write_test');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return null;
  } on FileSystemException catch (e) {
    final why = e.osError?.message ?? e.message;
    return 'NaviVibe can’t write to this folder ($why). Choose another one.';
  }
}

typedef CommandRunner = Future<ProcessResult> Function(String exe, List<String> args);

Future<ProcessResult> _run(String exe, List<String> args) => Process.run(exe, args);

/// Free space, in bytes, on the volume holding [path]. Null when the platform
/// does not say. [run] and [android] are test seams.
Future<int?> freeSpaceBytes(String path, {CommandRunner run = _run, bool? android}) async {
  try {
    if (android ?? (!kIsWeb && Platform.isAndroid)) {
      final mb = await DiskSpacePlus().getFreeDiskSpaceForPath(path);
      return mb == null ? null : (mb * 1024 * 1024).round();
    }
    if (Platform.isWindows) {
      final root = _windowsDrive(path);
      if (root == null) return null;
      final r = await run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-PSDrive -Name ${root[0]}).Free',
      ]);
      return r.exitCode == 0 ? int.tryParse(r.stdout.toString().trim()) : null;
    }
    // POSIX: `df -Pk` prints 1K blocks; the 4th column of the last line is available.
    final r = await run('df', ['-Pk', path]);
    if (r.exitCode != 0) return null;
    return parseDfAvailableBytes(r.stdout.toString());
  } catch (_) {
    return null;
  }
}

String? _windowsDrive(String path) {
  final m = RegExp(r'^([A-Za-z]):').firstMatch(path);
  return m?.group(1);
}

/// Available bytes from `df -Pk` output.
int? parseDfAvailableBytes(String out) {
  final lines = out.trim().split('\n');
  if (lines.length < 2) return null;
  final cols = lines.last.trim().split(RegExp(r'\s+'));
  if (cols.length < 4) return null;
  final kb = int.tryParse(cols[3]);
  return kb == null ? null : kb * 1024;
}

class MoveResult {
  final int moved;
  final int failed;
  const MoveResult(this.moved, this.failed);
}

/// Moves every file in [from] into [to] (rename when both are on one volume,
/// copy then delete otherwise), reporting (done, total). A file that cannot be
/// moved stays where it is and is counted in [MoveResult.failed], so a
/// partial move never loses a download. Files already in [to] are kept.
Future<MoveResult> moveDirectoryFiles(
  String from,
  String to, {
  void Function(int done, int total)? onProgress,
}) async {
  final src = Directory(from);
  if (!await src.exists() || src.absolute.path == Directory(to).absolute.path) {
    return const MoveResult(0, 0);
  }
  await Directory(to).create(recursive: true);
  final files = [
    await for (final e in src.list(followLinks: false))
      if (e is File) e,
  ];
  var moved = 0, failed = 0;
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final target = File('$to${Platform.pathSeparator}${f.uri.pathSegments.last}');
    try {
      if (await target.exists()) {
        await f.delete();
      } else {
        try {
          await f.rename(target.path);
        } on FileSystemException {
          // Different volume: copy, verify the size, then remove the original.
          await f.copy(target.path);
          if (await target.length() != await f.length()) {
            await target.delete();
            throw const FileSystemException('Copy was incomplete');
          }
          await f.delete();
        }
      }
      moved++;
    } on FileSystemException {
      failed++;
    }
    onProgress?.call(i + 1, files.length);
  }
  return MoveResult(moved, failed);
}

/// Total bytes in [dir] (files only), without blocking the UI isolate.
Future<int> directorySize(String dir) async {
  final d = Directory(dir);
  if (!await d.exists()) return 0;
  var total = 0;
  await for (final e in d.list(followLinks: false)) {
    if (e is File) total += await e.length();
  }
  return total;
}
