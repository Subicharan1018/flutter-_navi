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

class DownloadStateNotifier extends Notifier<Map<String, SongDownloadState>> {
  @override
  Map<String, SongDownloadState> build() {
    // Synchronously seed the map with all songs already on disk so the UI
    // is correct from the very first frame.  OfflineService.getDownloadedSongIds()
    // reads from SharedPreferences which is already initialised before main()
    // calls runApp().
    final offline = ref.watch(offlineServiceProvider);
    final ids = offline.getDownloadedSongIds();
    return {
      for (final id in ids)
        id: SongDownloadState(
          songId: id,
          status: SongDownloadStatus.downloaded,
        ),
    };
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
  Future<void> downloadSong(Song song) async {
    final current = statusOf(song.id);
    if (current == SongDownloadStatus.downloaded ||
        current == SongDownloadStatus.queued ||
        current == SongDownloadStatus.downloading) {
      return; // guard: no-op
    }

    _set(song.id, SongDownloadStatus.queued);
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
