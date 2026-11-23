import 'dart:async';

import '../models/song.dart';

/// What a stretch of downloading came to, handed over when the queue empties.
class DownloadBatchResult {
  final int succeeded;
  final int failed;

  /// Title of the last song that finished well (names a one-song batch).
  final String? lastTitle;
  const DownloadBatchResult({required this.succeeded, required this.failed, this.lastTitle});
}

class _Job {
  _Job(this.song, this.announce);
  final Song song;
  final bool announce;
  final Completer<bool> done = Completer<bool>();
  int attempts = 0;
  bool cancelled = false;
}

/// Runs song downloads with a limit on how many go at once, retries a failed
/// one a couple of times (the next attempt resumes the partial file), waits for
/// the network instead of burning attempts while offline, and reports when the
/// whole stretch of work is over. Pure Dart: the actual transfer is [run].
class DownloadQueue {
  DownloadQueue({
    required this.run,
    required this.onJobStart,
    required this.onJobEnd,
    this.onBatchDone,
    this.onChanged,
    this.onCancelRunning,
    this.isOnline,
    this.waitForNetwork,
    this.concurrency = 2,
    this.maxAttempts = 3,
    this.backoff = const [Duration(seconds: 5), Duration(seconds: 20)],
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  /// One attempt at [song]; true when the file is complete.
  final Future<bool> Function(Song song) run;
  final void Function(Song song) onJobStart;

  /// [ok] false with [cancelled] false is a real failure.
  final void Function(Song song, {required bool ok, required bool cancelled}) onJobEnd;
  final void Function(DownloadBatchResult result)? onBatchDone;

  /// The set of outstanding songs or the counts changed.
  final void Function()? onChanged;

  /// A running job was cancelled: stop its transfer.
  final void Function(String songId)? onCancelRunning;
  final Future<bool> Function()? isOnline;

  /// Completes true when the network is back, false if it did not return in time.
  final Future<bool> Function()? waitForNetwork;
  final int concurrency;
  final int maxAttempts;
  final List<Duration> backoff;
  final Future<void> Function(Duration) _delay;

  final List<_Job> _pending = [];
  final Map<String, _Job> _running = {};

  int _total = 0;
  int _finished = 0;
  int _ok = 0;
  int _failed = 0;
  String? _lastTitle;

  /// Jobs not finished yet (waiting or running).
  int get outstanding => _pending.length + _running.length;
  int get batchTotal => _total;
  int get batchFinished => _finished;

  /// The songs still to do, for saving across a restart.
  List<Song> get outstandingSongs => [for (final j in _running.values) j.song, for (final j in _pending) j.song];

  bool isActive(String songId) => _running.containsKey(songId) || _pending.any((j) => j.song.id == songId);

  /// Adds [song]; the future completes with whether it was downloaded.
  /// [announce] false keeps it out of the batch summary (background auto-download).
  Future<bool> enqueue(Song song, {bool announce = true}) => enqueueAll([song], announce: announce).single;

  /// Adds every song at once, so the count shown while downloading is right from the start.
  List<Future<bool>> enqueueAll(List<Song> songs, {bool announce = true}) {
    final futures = <Future<bool>>[];
    for (final song in songs) {
      final existing = _running[song.id] ?? _pending.where((j) => j.song.id == song.id).firstOrNull;
      if (existing != null) {
        futures.add(existing.done.future);
        continue;
      }
      final job = _Job(song, announce);
      _pending.add(job);
      _total++;
      futures.add(job.done.future);
    }
    onChanged?.call();
    _pump();
    return futures;
  }

  void cancel(String songId) {
    final queued = _pending.where((j) => j.song.id == songId).firstOrNull;
    if (queued != null) {
      _pending.remove(queued);
      _finish(queued, ok: false, cancelled: true);
      return;
    }
    final job = _running[songId];
    if (job != null) {
      job.cancelled = true;
      onCancelRunning?.call(songId);
    }
  }

  void cancelAll() {
    for (final j in _pending.toList()) {
      _pending.remove(j);
      _finish(j, ok: false, cancelled: true);
    }
    for (final j in _running.values.toList()) {
      j.cancelled = true;
      onCancelRunning?.call(j.song.id);
    }
  }

  void _pump() {
    while (_running.length < concurrency && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      _running[job.song.id] = job;
      unawaited(_work(job));
    }
  }

  Future<void> _work(_Job job) async {
    var ok = false;
    try {
      while (true) {
        if (job.cancelled) break;
        if (isOnline != null && !await _online()) {
          // No network: wait for it instead of spending an attempt.
          final back = await (waitForNetwork?.call() ?? Future.value(false));
          if (job.cancelled) break;
          if (!back) break;
          continue;
        }
        onJobStart(job.song);
        ok = await run(job.song);
        if (ok || job.cancelled) break;
        job.attempts++;
        if (job.attempts >= maxAttempts) break;
        await _delay(backoff[(job.attempts - 1).clamp(0, backoff.length - 1)]);
      }
    } catch (_) {
      ok = false;
    }
    _running.remove(job.song.id);
    _finish(job, ok: ok && !job.cancelled, cancelled: job.cancelled);
    _pump();
  }

  Future<bool> _online() async {
    try {
      return await isOnline!();
    } catch (_) {
      return true; // can't tell: try
    }
  }

  void _finish(_Job job, {required bool ok, required bool cancelled}) {
    _finished++;
    if (job.announce && !cancelled) {
      if (ok) {
        _ok++;
        _lastTitle = job.song.title;
      } else {
        _failed++;
      }
    }
    onJobEnd(job.song, ok: ok, cancelled: cancelled);
    if (!job.done.isCompleted) job.done.complete(ok);
    onChanged?.call();
    if (outstanding == 0) {
      final result = DownloadBatchResult(succeeded: _ok, failed: _failed, lastTitle: _lastTitle);
      final announced = _ok + _failed > 0;
      _total = 0;
      _finished = 0;
      _ok = 0;
      _failed = 0;
      _lastTitle = null;
      if (announced) onBatchDone?.call(result);
      onChanged?.call();
    }
  }
}
