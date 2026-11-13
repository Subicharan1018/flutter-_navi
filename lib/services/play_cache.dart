import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Songs heard in a session, kept on disk so going back to them (or playing
/// them again) needs no network and no re-buffering.
///
/// Files are named by **song id + quality**, never by URL: the stream URL
/// carries a login token and the transcoding settings, and either changing
/// used to make a cached song look new. Quality is `orig` for the original
/// file or `<format>-<kbps>` for a transcode.
///
/// The folder is the index: a finished file is `<id>.<quality>.audio` with a
/// `.mime` sidecar; downloads in flight are `.dl` or `.part`. It lives in the
/// app-support folder (not the OS-clearable temp folder), so it survives
/// restarts, and is trimmed least-recently-used first to [maxBytes].
///
/// On Android just_audio's `LockCachingAudioSource` writes the same files
/// while it streams; this class also downloads the next songs ahead of time
/// (needed on desktop, where that source is not available).
class PlayCache {
  PlayCache({Directory? dir, int Function()? maxBytes, Dio Function()? dioFactory})
      : _dir = dir,
        _maxBytes = maxBytes ?? (() => 500 * 1024 * 1024),
        _dioFactory = dioFactory ?? Dio.new;

  /// The app-wide cache.
  static final PlayCache instance = PlayCache();

  Directory? _dir;
  int Function() _maxBytes;
  final Dio Function() _dioFactory;
  final Set<String> _inFlight = {};

  /// Bumps whenever files are added or removed, so a size readout can refresh.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Tests and start-up: where files live and how big the cache may grow.
  void configure({Directory? dir, int Function()? maxBytes}) {
    if (dir != null) _dir = dir;
    if (maxBytes != null) _maxBytes = maxBytes;
  }

  Future<void> initialize() async {
    if (_dir == null) {
      final base = await getApplicationSupportDirectory();
      _dir = Directory('${base.path}${Platform.pathSeparator}play_cache');
    }
    await _dir!.create(recursive: true);
    await _sweepStale();
  }

  /// `orig`, or `<format>-<kbps>` when the server transcodes.
  static String qualityKey({int? bitrate, String? format}) {
    final f = (format == null || format.isEmpty || format == 'raw') ? null : format;
    final b = (bitrate == null || bitrate <= 0) ? null : bitrate;
    if (f == null && b == null) return 'orig';
    return '${f ?? 'raw'}-${b ?? 0}';
  }

  /// Where the finished copy of [songId] at [quality] is (or will be).
  /// Null before [initialize]/[configure].
  File? fileFor(String songId, String quality) {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}${_safe(songId)}.${_safe(quality)}.audio');
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  /// The finished copy, marked as just used, or null.
  Future<File?> completeFile(String songId, String quality) async {
    final f = fileFor(songId, quality);
    if (f == null) return null;
    try {
      if (!await f.exists() || await f.length() == 0) return null;
      await f.setLastModified(DateTime.now()); // LRU: this one is in use
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] into the cache unless it is already there or on its way.
  /// Never throws: a failed prefetch just leaves the song to stream.
  Future<void> prefetch(String songId, String quality, Uri url, {Set<String> keep = const {}}) async {
    final target = fileFor(songId, quality);
    if (target == null) return;
    final key = target.path;
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);
    final tmp = File('$key.dl');
    try {
      if (await target.exists()) return;
      final dio = _dioFactory();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 60);
      final res = await dio.download(url.toString(), tmp.path);
      final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      if (!ok || await tmp.length() == 0) {
        await _quietDelete(tmp);
        return;
      }
      // just_audio's caching source reads the type from this sidecar.
      await File('$key.mime').writeAsString(res.headers.value('content-type') ?? 'audio/mpeg');
      if (await target.exists()) {
        await _quietDelete(tmp); // the streaming source finished first
      } else {
        await tmp.rename(key);
      }
      revision.value++;
      await evict(keep: keep);
    } catch (e) {
      debugPrint('[PlayCache] prefetch $songId: $e');
      await _quietDelete(tmp);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Total bytes the cache holds, partial downloads included.
  Future<int> sizeBytes() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Trims to the size limit, least recently used first, never touching
  /// [keep] (the songs around the one playing). Returns bytes freed.
  Future<int> evict({Set<String> keep = const {}}) async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return 0;
    final finished = <({File file, int bytes, DateTime used, String songId})>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      int bytes;
      try {
        bytes = await e.length();
      } catch (_) {
        continue;
      }
      total += bytes;
      if (name.endsWith('.audio')) {
        finished.add((
          file: e,
          bytes: bytes,
          used: (await e.lastModified()),
          songId: name.substring(0, name.indexOf('.')),
        ));
      }
    }
    final limit = _maxBytes();
    if (total <= limit) return 0;
    finished.sort((a, b) => a.used.compareTo(b.used));
    var freed = 0;
    for (final f in finished) {
      if (total - freed <= limit) break;
      if (keep.map(_safe).contains(f.songId)) continue;
      await _quietDelete(f.file);
      await _quietDelete(File('${f.file.path}.mime'));
      freed += f.bytes;
    }
    if (freed > 0) revision.value++;
    return freed;
  }

  /// Empties the cache (for the Clear button). Copies being written right now
  /// are left alone.
  Future<void> clear() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final path = e.path;
      if (_inFlight.any((p) => path.startsWith(p))) continue;
      await _quietDelete(e);
    }
    revision.value++;
  }

  /// Half-written downloads from an earlier run (a quit mid-download) are
  /// useless after a day; remove them so they do not sit in the size count.
  Future<void> _sweepStale() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final e in _dir!.list()) {
      if (e is! File) continue;
      final n = e.path;
      if ((n.endsWith('.dl') || n.endsWith('.part')) && (await e.lastModified()).isBefore(cutoff)) {
        await _quietDelete(e);
      }
    }
  }

  Future<void> _quietDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
