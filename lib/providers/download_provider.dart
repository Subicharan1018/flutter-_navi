import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../models/download_state.dart';
import '../offline_service.dart';
import '../services/android_integration.dart';
import '../services/app_notifier.dart';
import '../services/download_keep_alive.dart';
import '../services/download_notices.dart';
import '../services/download_queue.dart';
import 'settings_provider.dart';

/// Keeps the app running while downloads go in the background (Android).
/// Override in tests.
final downloadKeepAliveProvider = Provider<DownloadKeepAlive>((ref) => DownloadKeepAlive());

/// Waits between a failed attempt and the next (the partial file resumes).
/// Overridden in tests.
final downloadRetryBackoffProvider = Provider<List<Duration>>((ref) => const [Duration(seconds: 5), Duration(seconds: 20)]);

/// The unfinished downloads, saved so a killed app can carry on.
final pendingDownloadStoreProvider = Provider<PendingDownloadStore>((ref) => const PendingDownloadStore());

// ---------------------------------------------------------------------------
// DownloadStateNotifier
// ---------------------------------------------------------------------------

/// Riverpod-managed per-song download tracker.
///
/// State is a map of songId → [SongDownloadState].  Songs that have never
/// been touched are **not** in the map; callers use [statusOf] which falls
/// back to [SongDownloadStatus.notDownloaded].
///
/// Uses [OfflineService] singleton directly (it is a factory singleton, not
/// wired through Riverpod) and reads [subsonicServiceProvider] via
/// [ref.read] when a network download is required.
final offlineServiceProvider = Provider<OfflineService>((ref) {
  return OfflineService();
});

/// Changes when covers are saved to or removed from the downloads folder after
/// the fact (a backfill, a delete), so tiles that show them repaint.
final savedCoversRevisionProvider = Provider<int>((ref) {
  final notifier = ref.watch(offlineServiceProvider).coversChanged;
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  return notifier.value;
});

/// Bytes used by downloads; recomputed whenever the set of downloads changes.
final downloadedBytesProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(downloadStateProvider.select((m) => m.length));
  return ref.read(offlineServiceProvider).getDownloadedSize();
});

/// Provides the [Connectivity] instance used for pre-flight checks.
/// Override in tests to avoid platform channel initialisation.
final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

/// Lets a progress update through at most every [minInterval], or sooner when
/// it moved by at least [minStep]. Network chunks arrive far faster than the UI
/// can show; completion and errors bypass this (they go through `_set`).
class DownloadProgressThrottle {
  DownloadProgressThrottle({
    this.minInterval = const Duration(milliseconds: 250),
    this.minStep = 0.01,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration minInterval;
  final double minStep;
  final DateTime Function() _now;
  DateTime? _lastAt;
  double _lastValue = 0;

  bool shouldEmit(double progress) {
    final now = _now();
    final last = _lastAt;
    if (last != null &&
        now.difference(last) < minInterval &&
        (progress - _lastValue).abs() < minStep) {
      return false;
    }
    _lastAt = now;
    _lastValue = progress;
    return true;
  }
}

class DownloadStateNotifier extends Notifier<Map<String, SongDownloadState>> {
  @override
  Map<String, SongDownloadState> build() {
    // Synchronously seed the map from SharedPreferences so the UI is correct
    // from the very first frame.  SharedPreferences is initialised before
    // runApp() so this read is always fast.
    //
    // BUG-1 FIX (Option 2 — post-build async reconcile):
    // We do NOT call isSongDownloaded() here because that calls
    // File.existsSync() — blocking disk I/O on the main thread, proportional
    // to library size.  Instead, we schedule an async reconciliation that
    // verifies file existence off the fast-path and patches state quietly.
    final offline = ref.watch(offlineServiceProvider);
    final ids = offline.getDownloadedSongIds();
    _setUpQueue();

    // Schedule reconciliation for the next microtask so build() returns
    // synchronously (Notifier.build must be synchronous).
    scheduleMicrotask(() => _reconcileWithDisk(offline, ids));

    return {
      for (final id in ids)
        id: SongDownloadState(
          songId: id,
          status: SongDownloadStatus.downloaded,
        ),
    };
  }

  /// Verifies that every ID in [ids] still has a file on disk.
  ///
  /// Uses [File.exists()] (async, non-blocking) so this never jams the main
  /// thread regardless of library size.  Any ID whose file is gone is silently
  /// demoted to [SongDownloadStatus.notDownloaded] and removed from state.
  Future<void> _reconcileWithDisk(
    OfflineService offline,
    List<String> ids,
  ) async {
    final orphans = <String>[];
    for (final id in ids) {
      final exists = await offline.isSongDownloadedAsync(id);
      if (!exists) orphans.add(id);
    }
    if (orphans.isEmpty) return;

    final updated = Map<String, SongDownloadState>.from(state);
    for (final id in orphans) {
      updated.remove(id);
    }
    state = updated;
  }

  // -------------------------------------------------------------------------
  // Public query API
  // -------------------------------------------------------------------------

  /// Returns the current download status for [songId].
  /// Defaults to [SongDownloadStatus.notDownloaded] if unknown.
  SongDownloadStatus statusOf(String songId) {
    return state[songId]?.status ?? SongDownloadStatus.notDownloaded;
  }

  // -------------------------------------------------------------------------
  // Single-song download
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Queue: downloads run through a [DownloadQueue] (two at a time), kept alive
  // in the background by [DownloadKeepAlive] and saved so a killed app resumes.
  // -------------------------------------------------------------------------

  late DownloadQueue _queue;

  void _setUpQueue() {
    final offline = ref.read(offlineServiceProvider);
    final keepAlive = ref.read(downloadKeepAliveProvider);
    final store = ref.read(pendingDownloadStoreProvider);
    _queue = DownloadQueue(
      run: _performDownload,
      onJobStart: (song) {
        if (ref.mounted) _set(song.id, SongDownloadStatus.downloading, progress: 0.0);
      },
      onJobEnd: (song, {required ok, required cancelled}) {
        if (!ref.mounted) return;
        if (cancelled) {
          final next = Map<String, SongDownloadState>.from(state)..remove(song.id);
          state = next;
        } else if (ok) {
          _set(song.id, SongDownloadStatus.downloaded, progress: 1.0);
        } else {
          _setFailed(song.id, 'Download failed');
        }
      },
      onBatchDone: (r) => unawaited(postDownloadNotices(r)),
      onChanged: () {
        keepAlive.update(done: _queue.batchFinished, total: _queue.batchTotal);
        unawaited(store.write(_queue.outstandingSongs));
      },
      onCancelRunning: offline.cancelDownload,
      backoff: ref.read(downloadRetryBackoffProvider),
      isOnline: _isOnline,
      waitForNetwork: _waitForNetwork,
    );
    // The "Stop" button on the ongoing notification.
    AndroidIntegration.onDownloadStopRequested = cancelAll;
    ref.onDispose(() {
      if (AndroidIntegration.onDownloadStopRequested == cancelAll) AndroidIntegration.onDownloadStopRequested = null;
    });
  }

  Future<bool> _isOnline() async {
    final results = await ref.read(connectivityProvider).checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  /// Waits (up to 15 minutes) for the network to come back; false if it did not.
  Future<bool> _waitForNetwork() async {
    try {
      final c = ref.read(connectivityProvider);
      return await c.onConnectivityChanged
          .firstWhere((r) => !r.contains(ConnectivityResult.none))
          .timeout(const Duration(minutes: 15))
          .then((_) => true);
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Single-song download
  // -------------------------------------------------------------------------

  /// Downloads [song] from the Subsonic server.
  ///
  /// - Guards against multi-tap: if the song is already active or downloaded,
  ///   this is a no-op.
  /// - Transitions: notDownloaded → queued → downloading (with progress) →
  ///   downloaded | failed. The queue retries a failed attempt and resumes the
  ///   partial file; [notify] false keeps it out of the finished notification.
  ///
  /// BUG-2 FIX: Pre-flight connectivity check gives immediate feedback when
  /// the device is offline instead of letting Dio hang indefinitely.
  ///
  /// connectivity_plus v7.1.1 returns `List<ConnectivityResult>` — verified
  /// against pubspec.lock (sha: 62ffa266).
  Future<void> downloadSong(Song song, {bool notify = true}) async {
    final current = statusOf(song.id);
    if (current == SongDownloadStatus.downloaded ||
        current == SongDownloadStatus.queued ||
        current == SongDownloadStatus.downloading) {
      return; // guard: no-op
    }

    // Set to queued immediately to prevent parallel synchronous calls
    // from slipping past the guard while the connectivity check yields.
    _set(song.id, SongDownloadStatus.queued);

    // BUG-2 FIX: Pre-flight connectivity check.
    if (!await _isOnline()) {
      _setFailed(song.id, 'No internet connection');
      return;
    }

    if (notify) unawaited(AppNotifier.prime()); // while the app is open: the prompt can't show later
    await _queue.enqueue(song, announce: notify);
  }

  /// One attempt at [song]; progress reaches the UI throttled.
  Future<bool> _performDownload(Song song) async {
    try {
      final subsonicService = ref.read(subsonicServiceProvider);
      final offlineService = ref.read(offlineServiceProvider);
      final throttle = DownloadProgressThrottle();
      return await offlineService.downloadSong(
        song,
        subsonicService,
        onProgress: (p) {
          if (!ref.mounted || !throttle.shouldEmit(p)) return;
          state = {
            ...state,
            song.id: SongDownloadState(
              songId: song.id,
              status: SongDownloadStatus.downloading,
              progress: p,
            ),
          };
        },
      );
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Bulk playlist download
  // -------------------------------------------------------------------------

  /// Downloads every song in [songs] that is not already downloaded.
  ///
  /// All eligible songs are immediately set to [SongDownloadStatus.queued];
  /// the queue then runs a couple at a time, and one notification summarises
  /// the batch when it ends.
  Future<void> downloadPlaylist(List<Song> songs) async {
    final toDownload = songs
        .where((s) => statusOf(s.id) == SongDownloadStatus.notDownloaded)
        .toList();

    if (toDownload.isEmpty) return;

    // Mark all as queued atomically so the UI shows progress immediately.
    state = {
      ...state,
      for (final s in toDownload)
        s.id: SongDownloadState(
          songId: s.id,
          status: SongDownloadStatus.queued,
        ),
    };

    unawaited(AppNotifier.prime());
    await Future.wait(_queue.enqueueAll(toDownload));
  }

  /// Carries on with the songs a previous run of the app had not finished (the
  /// app was closed or killed mid-download). Partial files resume where they stopped.
  Future<void> resumePending() async {
    final offline = ref.read(offlineServiceProvider);
    final saved = ref.read(pendingDownloadStoreProvider).read();
    final todo = [
      for (final s in saved)
        if (!await offline.isSongDownloadedAsync(s.id) && !_queue.isActive(s.id)) s,
    ];
    if (!ref.mounted) return;
    if (todo.isEmpty) {
      if (saved.isNotEmpty && _queue.outstanding == 0) await ref.read(pendingDownloadStoreProvider).write(const []);
      return;
    }
    state = {
      ...state,
      for (final s in todo) s.id: SongDownloadState(songId: s.id, status: SongDownloadStatus.queued),
    };
    await Future.wait(_queue.enqueueAll(todo));
  }

  /// Stops everything waiting or running (the notification's Stop button).
  /// Songs go back to "not downloaded"; partial files are removed.
  void cancelAll() => _queue.cancelAll();

  /// Stops one song's download.
  void cancel(String songId) => _queue.cancel(songId);

  // -------------------------------------------------------------------------
  // Delete
  // -------------------------------------------------------------------------

  /// Removes the downloaded file and updates state to [SongDownloadStatus.notDownloaded].
  Future<void> deleteSong(String songId) async {
    await ref.read(offlineServiceProvider).deleteSong(songId);
    final updated = Map<String, SongDownloadState>.from(state);
    updated.remove(songId);
    state = updated;
  }

  /// Removes every downloaded file. Goes through the notifier so every
  /// download badge and the Downloaded list update at once.
  Future<void> deleteAll() async {
    await ref.read(offlineServiceProvider).deleteAllDownloads();
    state = const {};
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _set(String songId, SongDownloadStatus status, {double progress = 0.0}) {
    state = {
      ...state,
      songId: SongDownloadState(
        songId: songId,
        status: status,
        progress: progress,
      ),
    };
  }

  void _setFailed(String songId, String message) {
    state = {
      ...state,
      songId: SongDownloadState(
        songId: songId,
        status: SongDownloadStatus.failed,
        errorMessage: message,
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global provider for per-song download state.
///
/// Watch `downloadStateProvider.select(...)` in widgets for minimal rebuilds.
final downloadStateProvider =
    NotifierProvider<DownloadStateNotifier, Map<String, SongDownloadState>>(
      DownloadStateNotifier.new,
    );
