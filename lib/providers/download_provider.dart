import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../models/download_state.dart';
import '../offline_service.dart';
import 'settings_provider.dart';

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

/// Provides the [Connectivity] instance used for pre-flight checks.
/// Override in tests to avoid platform channel initialisation.
final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

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

  /// Returns the download progress [0.0–1.0] for [songId].
  double progressOf(String songId) => state[songId]?.progress ?? 0.0;

  // -------------------------------------------------------------------------
  // Single-song download
  // -------------------------------------------------------------------------

  /// Downloads [song] from the Subsonic server.
  ///
  /// - Guards against multi-tap: if the song is already active or downloaded,
  ///   this is a no-op.
  /// - Transitions: notDownloaded → queued → downloading (with progress) →
  ///   downloaded | failed.
  /// - The menu stays open: Navigator.pop() is NOT called here.
  /// Downloads [song] from the Subsonic server.
  ///
  /// BUG-2 FIX: Pre-flight connectivity check gives immediate feedback when
  /// the device is offline instead of letting Dio hang indefinitely.
  ///
  /// connectivity_plus v7.1.1 returns `List<ConnectivityResult>` — verified
  /// against pubspec.lock (sha: 62ffa266).
  Future<void> downloadSong(Song song) async {
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
    final connectivity = ref.read(connectivityProvider);
    final results = await connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      _setFailed(song.id, 'No internet connection');
      return;
    }

    await _performDownload(song);
  }

  Future<void> _performDownload(Song song) async {
    final subsonicService = ref.read(subsonicServiceProvider);

    try {
      _set(song.id, SongDownloadStatus.downloading, progress: 0.0);

      final offlineService = ref.read(offlineServiceProvider);
      final success = await offlineService.downloadSong(
        song,
        subsonicService,
        onProgress: (p) {
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

      if (success) {
        _set(song.id, SongDownloadStatus.downloaded, progress: 1.0);
      } else {
        _setFailed(song.id, 'Download failed');
      }
    } catch (e) {
      _setFailed(song.id, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // Bulk playlist download
  // -------------------------------------------------------------------------

  /// Downloads every song in [songs] that is not already downloaded.
  ///
  /// All eligible songs are immediately set to [SongDownloadStatus.queued],
  /// then downloaded sequentially so bandwidth is not thrashed.
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

    for (final song in toDownload) {
      await _performDownload(song);
    }
  }

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
