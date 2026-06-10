import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/settings_provider.dart';
import '../providers/download_provider.dart';
import 'subsonic_service.dart';

// =============================================================================
// ScrobbleService
//
// Handles Subsonic scrobble calls (now-playing + submission).
//
// Feedback to the shuffle/ML model (POST /feedback) is handled separately by
// sendShuffleFeedback() in player_provider.dart — NOT here. The old
// ListeningLogService.logPlay() call was removed because it duplicated the
// POST /feedback request with hardcoded inaccurate data (listen_ratio: 1.0,
// end_reason: 'natural' regardless of actual user behavior).
//
// Both scrobble calls are fire-and-forget (unawaited) so they never block
// playback.
// =============================================================================

final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  return ScrobbleService(
    ref.watch(subsonicServiceProvider),
    ref.watch(connectivityProvider),
  );
});

class ScrobbleService {
  final SubsonicService _api;
  final Connectivity _connectivity;

  ScrobbleService(this._api, this._connectivity);

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
  /// (submission=true).
  ///
  /// Fire-and-forget — swallows all errors and does nothing if offline.
  /// The [song] parameter is retained for API compatibility with existing
  /// call sites but is no longer used for listening-log submission.
  void submit(String songId, {Song? song}) async {
    if (await _isOffline()) return;

    // ── Subsonic scrobble ────────────────────────────────────────────────────
    unawaited(_api.scrobble(songId, submission: true));
  }
}
