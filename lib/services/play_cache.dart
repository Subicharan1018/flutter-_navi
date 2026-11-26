import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fast_start.dart' show ThroughputTracker;

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
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, ({String songId, CancelToken token})> _tokens = {};

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

  /// Sync twin of [completeFile] for the skip path (one stat, no LRU touch).
  bool hasCompleteSync(String songId, String quality) {
    try {
      final f = fileFor(songId, quality);
      return f != null && f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// True when the finished copy, or at least [minBytes] of a copy being
  /// written (by the streaming source or a prefetch), is on disk: the song is
  /// already preloaded and needs no fast start.
  Future<bool> isWarm(String songId, String quality, {int minBytes = 256 * 1024}) async {
    final f = fileFor(songId, quality);
    if (f == null) return false;
    for (final path in [f.path, '${f.path}.part', '${f.path}.dl']) {
      try {
        final file = File(path);
        if (await file.exists() && await file.length() >= minBytes) return true;
      } catch (_) {}
    }
    return false;
  }

  // ── Head start: the first bytes of songs about to be played ────────────────
  /// How much of a song's start is kept ahead of time (about 3-5 s of FLAC).
  static const int headBytes = 1536 * 1024;

  final Map<String, Future<void>> _headFlight = {};
  final Map<String, _Job> _jobs = {};

  File? _headFile(String songId, String quality) {
    final f = fileFor(songId, quality);
    return f == null ? null : File('${f.path}.head');
  }

  File? _headMeta(String songId, String quality) {
    final f = fileFor(songId, quality);
    return f == null ? null : File('${f.path}.head.json');
  }

  /// The saved head of a song (its size, the whole song's size and type), or
  /// null. Cheap: two stats and one small read, no network.
  ({File file, int length, int total, String mime})? headSync(String songId, String quality) {
    try {
      final file = _headFile(songId, quality);
      final meta = _headMeta(songId, quality);
      if (file == null || meta == null || !file.existsSync() || !meta.existsSync()) return null;
      final m = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
      final length = file.lengthSync();
      final total = (m['total'] as num?)?.toInt() ?? 0;
      if (length <= 0 || total <= length) return null;
      return (file: file, length: length, total: total, mime: (m['mime'] as String?) ?? 'audio/mpeg');
    } catch (_) {
      return null;
    }
  }

  /// Saves the first [headBytes] of the song so a skip onto it can start
  /// playing at once. Needs a server that answers byte ranges (an original
  /// file, not a live transcode); otherwise nothing is kept. Never throws.
  Future<void> prefetchHead(String songId, String quality, Uri url) {
    final target = fileFor(songId, quality);
    if (target == null) return Future.value();
    final key = target.path;
    final running = _headFlight[key];
    if (running != null) return running;
    final job = _fetchHead(songId, quality, url).whenComplete(() {
      // (a block, not `=> remove(...)`: returning the future would make it wait on itself)
      _headFlight.remove(key);
    });
    _headFlight[key] = job;
    return job;
  }

  Future<void> _fetchHead(String songId, String quality, Uri url) async {
    final target = fileFor(songId, quality)!;
    final head = _headFile(songId, quality)!;
    final meta = _headMeta(songId, quality)!;
    final token = CancelToken();
    try {
      if (await target.exists() || headSync(songId, quality) != null) return;
      final dio = _dioFactory();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 20);
      final res = await dio.get<ResponseBody>(
        url.toString(),
        options: Options(responseType: ResponseType.stream, headers: {'Range': 'bytes=0-${headBytes - 1}'}),
        cancelToken: token,
      );
      final total = int.tryParse((res.headers.value('content-range') ?? '').split('/').last) ?? 0;
      if (res.statusCode != 206 || total <= headBytes) {
        token.cancel('no range support');
        return;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res.data!.stream) {
        builder.add(chunk);
        if (builder.length >= headBytes) break;
      }
      token.cancel('head complete');
      if (builder.length < 64 * 1024) return;
      final bytes = builder.takeBytes();
      final tmp = File('${head.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await meta.writeAsString(jsonEncode({
        'total': total,
        'mime': res.headers.value('content-type') ?? 'audio/mpeg',
      }));
      await tmp.rename(head.path);
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) debugPrint('[PlayCache] head $songId: $e');
      await _quietDelete(head);
      await _quietDelete(meta);
    }
  }

  /// Bytes [start, end) of the song as they arrive. Plays from the finished
  /// file, or from the download in flight (started here from the saved head
  /// if none is running), so the player and the cache share one request.
  Stream<List<int>> readThrough(
    String songId,
    String quality,
    Uri url, {
    required int start,
    required int end,
    required int total,
  }) async* {
    final target = fileFor(songId, quality)!;
    if (await target.exists()) {
      yield* target.openRead(start, end);
      return;
    }
    var job = _jobs[target.path];
    if (job == null) {
      unawaited(_resume(songId, quality, url, total));
      job = _jobs[target.path];
    }
    // A seek far beyond the download: ask for just that part.
    if (job == null || start > job.bytes + 2 * 1024 * 1024) {
      yield* _remoteRange(url, start, end);
      return;
    }
    var pos = start;
    while (pos < end) {
      final file = job.finished && await target.exists() ? target : job.file;
      if (pos < job.bytes || job.finished) {
        final want = [end - pos, 256 * 1024, if (!job.finished) job.bytes - pos].reduce((a, b) => a < b ? a : b);
        final got = await _readAt(file, pos, want);
        if (got.isNotEmpty) {
          yield got;
          pos += got.length;
          continue;
        }
        if (job.finished) {
          yield* _remoteRange(url, pos, end);
          return;
        }
      }
      try {
        await job.changed.first.timeout(const Duration(milliseconds: 400), onTimeout: () {});
      } on StateError {
        // The download ended between the check and the wait; loop and re-read.
      }
    }
  }

  Future<List<int>> _readAt(File f, int pos, int len) async {
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      await raf.setPosition(pos);
      return await raf.read(len);
    } catch (_) {
      return const [];
    } finally {
      await raf?.close();
    }
  }

  Stream<List<int>> _remoteRange(Uri url, int start, int end) async* {
    final res = await _dioFactory().get<ResponseBody>(
      url.toString(),
      options: Options(responseType: ResponseType.stream, headers: {'Range': 'bytes=$start-${end - 1}'}),
    );
    yield* res.data!.stream;
  }

  /// Continues a song from its saved head: copies the head, then appends the
  /// rest (a range request), and finishes like any other cached song.
  Future<void> _resume(String songId, String quality, Uri url, int total) {
    final target = fileFor(songId, quality)!;
    final key = target.path;
    final running = _inFlight[key];
    if (running != null) return running;
    final done = _download(songId, key, target, url, const {}, resumeTotal: total);
    _inFlight[key] = done;
    return done;
  }

  /// Downloads [url] into the cache unless it is already there or on its way.
  /// Never throws: a failed prefetch just leaves the song to stream.
  ///
  /// Asking for a song that is already on its way returns that download's
  /// future, so a caller can wait for the file. [cancelPrefetches] stops
  /// downloads for songs nobody is waiting for any more.
  Future<void> prefetch(String songId, String quality, Uri url, {Set<String> keep = const {}}) {
    final target = fileFor(songId, quality);
    if (target == null) return Future.value();
    final key = target.path;
    final running = _inFlight[key];
    if (running != null) return running;
    final done = _download(songId, key, target, url, keep);
    _inFlight[key] = done;
    return done;
  }

  /// Stops downloads in flight for every song not in [keepSongIds].
  void cancelPrefetches({Set<String> keepSongIds = const {}}) {
    for (final e in _tokens.values) {
      if (!keepSongIds.contains(e.songId) && !e.token.isCancelled) e.token.cancel('not needed');
    }
  }

  Future<void> _download(
    String songId,
    String key,
    File target,
    Uri url,
    Set<String> keep, {
    int? resumeTotal,
  }) async {
    final token = CancelToken();
    _tokens[key] = (songId: songId, token: token);
    final tmp = File('$key.dl');
    final job = _jobs[key] = _Job(tmp);
    final watch = Stopwatch()..start();
    try {
      if (await target.exists()) return;
      final dio = _dioFactory();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 60);
      String mime;
      if (resumeTotal != null) {
        // From the saved head: its bytes first, then the rest of the song.
        final head = _headFile(songId, _qualityOf(target));
        final h = headSync(songId, _qualityOf(target));
        if (head == null || h == null) throw StateError('head gone');
        await head.copy(tmp.path);
        job.advance(h.length);
        final res = await dio.get<ResponseBody>(
          url.toString(),
          options: Options(responseType: ResponseType.stream, headers: {'Range': 'bytes=${h.length}-'}),
          cancelToken: token,
        );
        if (res.statusCode != 206) throw StateError('range ignored (${res.statusCode})');
        final sink = tmp.openWrite(mode: FileMode.append);
        var written = h.length;
        try {
          await for (final chunk in res.data!.stream) {
            sink.add(chunk);
            await sink.flush();
            written += chunk.length;
            job.advance(written);
          }
        } finally {
          await sink.close();
        }
        if (written != resumeTotal) throw StateError('short download $written of $resumeTotal');
        mime = h.mime;
      } else {
        final res = await dio.download(
          url.toString(),
          tmp.path,
          cancelToken: token,
          onReceiveProgress: (count, _) => job.advance(count),
        );
        final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
        if (!ok || await tmp.length() == 0) {
          await _quietDelete(tmp);
          return;
        }
        mime = res.headers.value('content-type') ?? 'audio/mpeg';
      }
      ThroughputTracker.instance.add(await tmp.length(), watch.elapsed);
      // just_audio's caching source reads the type from this sidecar.
      await File('$key.mime').writeAsString(mime);
      if (await target.exists()) {
        await _quietDelete(tmp); // the streaming source finished first
      } else {
        // A player reading the growing file at this instant holds it open
        // (Windows refuses the rename); it lets go within milliseconds.
        for (var attempt = 0;; attempt++) {
          try {
            await tmp.rename(key);
            break;
          } on FileSystemException {
            if (attempt >= 8) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        }
      }
      revision.value++;
      await evict(keep: keep);
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) debugPrint('[PlayCache] prefetch $songId: $e');
      await _quietDelete(tmp);
    } finally {
      job.finish();
      _jobs.remove(key);
      _inFlight.remove(key);
      _tokens.remove(key);
      // The head is only a stand-in until the whole song is on disk.
      if (await target.exists()) {
        await _quietDelete(File('$key.head'));
        await _quietDelete(File('$key.head.json'));
      }
    }
  }

  /// `<id>.<quality>.audio` -> quality, to find the head beside it.
  String _qualityOf(File target) {
    final name = target.uri.pathSegments.last; // id.quality.audio
    final parts = name.split('.');
    return parts.length >= 3 ? parts[1] : 'orig';
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
      if (_inFlight.keys.any((p) => path.startsWith(p))) continue;
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
      final stale = n.endsWith('.dl') || n.endsWith('.part') || n.endsWith('.head') || n.endsWith('.head.json') || n.endsWith('.head.tmp');
      if (stale && (await e.lastModified()).isBefore(cutoff)) {
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

/// A download in flight: how many bytes of its `.dl` file are readable.
class _Job {
  _Job(this.file);
  final File file;
  int bytes = 0;
  bool finished = false;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changed => _changes.stream;

  void advance(int to) {
    if (to > bytes) bytes = to;
    _changes.add(null);
  }

  void finish() {
    finished = true;
    _changes.add(null);
    unawaited(_changes.close());
  }
}
