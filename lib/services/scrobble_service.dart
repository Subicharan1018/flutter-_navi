import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/local_library/logic/local_models.dart' show isLocalSongId;
import '../features/play_outbox/logic/play_outbox_providers.dart' show PlayRecorder, playRecorderProvider;
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
// sendShuffleFeedback() in player_provider.dart — NOT here.
//
// Both scrobble calls are fire-and-forget (unawaited) so they never block
// playback.
// =============================================================================

final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  return ScrobbleService(
    ref.watch(subsonicServiceProvider),
    ref.watch(connectivityProvider),
    recorder: ref.watch(playRecorderProvider),
  );
});

class ScrobbleService {
  final SubsonicService _api;
  final Connectivity _connectivity;
  final PlayRecorder? _recorder;

  ScrobbleService(this._api, this._connectivity, {PlayRecorder? recorder}) : _recorder = recorder;

  Future<bool> _isOffline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Notifies the server that [songId] is now playing (submission=false).
  ///
  /// Fire-and-forget — swallows all errors and does nothing if offline.
  void nowPlaying(String songId) async {
    if (isLocalSongId(songId) || await _isOffline()) return;
    unawaited(_api.scrobble(songId, submission: false));
  }

  /// Submits a completed play of [songId] to the Subsonic scrobble endpoint
  /// (submission=true).
  ///
  /// Fire-and-forget — swallows all errors and does nothing if offline.
  /// The [song] parameter is retained for API compatibility with existing
  /// call sites but is no longer used for listening-log submission.
  ///
  /// With a [playId] the play goes through the outbox: written now whether or
  /// not the network is up, dated [startedAtMs], and delivered immediately
  /// when online or on reconnect otherwise.
  void submit(String songId, {Song? song, String? playId, int? startedAtMs}) async {
    final recorder = playId == null ? null : _recorder;
    if (recorder != null) {
      try {
        await recorder.scrobbleQualified(
          playId: playId!,
          songId: songId,
          startedAtMs: startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
        return;
      } catch (_) {
        // Bookkeeping never breaks playback: fall through to the direct call.
      }
    }
    if (isLocalSongId(songId) || await _isOffline()) return;

    // ── Subsonic scrobble ────────────────────────────────────────────────────
    unawaited(_api.scrobble(songId, submission: true));
  }
}
