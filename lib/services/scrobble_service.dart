import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/settings_provider.dart';
import '../providers/download_provider.dart';
import 'subsonic_service.dart';
import 'listening_log_service.dart';

// =============================================================================
// ScrobbleService
//
// Handles Subsonic scrobble calls (now-playing + submission) alongside the new
// slim listening-log POST to the WebDAV endpoint.
//
// Both calls are fire-and-forget (unawaited) so they never block playback.
// =============================================================================

final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  return ScrobbleService(
    ref.watch(subsonicServiceProvider),
    ref.watch(connectivityProvider),
    ref.watch(listeningLogServiceProvider),
  );
});

class ScrobbleService {
  final SubsonicService _api;
  final Connectivity _connectivity;
  final ListeningLogService _listeningLog;

  ScrobbleService(this._api, this._connectivity, this._listeningLog);

  Future<bool> _isOffline() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.none);
  }

  /// Notifies the server that [songId] is now playing (submission=false).
  ///
  /// Fire-and-forget — swallows all errors and does nothing if offline.
  void nowPlaying(String songId) async {
    if (await _isOffline()) return;
    unawaited(_api.scrobble(songId, submission: false));
  }

  /// Submits a completed play of [songId] to the Subsonic scrobble endpoint
  /// (submission=true) **and** posts a slim listening-log entry to the WebDAV
  /// server.
  ///
  /// Both network calls are fire-and-forget. The listening log is silently
  /// queued for retry if the POST fails.
  ///
  /// [song] and [playedDuration] are optional for backward compatibility with
  /// existing call sites that only have a song ID.
  void submit(String songId, {Song? song}) async {
    if (await _isOffline()) return;

    // ── Subsonic scrobble ────────────────────────────────────────────────────
    unawaited(_api.scrobble(songId, submission: true));

    // ── Listening log ────────────────────────────────────────────────────────
    if (song != null) {
      // Resolve the full cover art URL using the existing SubsonicService client.
      final coverArtUrl = song.coverArt.isNotEmpty
          ? _api.getCoverArtUrl(song.coverArt)
          : null;
      unawaited(_listeningLog.logPlay(song: song, coverArtUrl: coverArtUrl));
    }
  }
}
