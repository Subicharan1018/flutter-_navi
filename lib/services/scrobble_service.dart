import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subsonic_service.dart';
import '../providers/download_provider.dart';
import '../providers/settings_provider.dart';

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

  void nowPlaying(String songId) async {
    if (await _isOffline()) return;
    unawaited(_api.scrobble(songId, submission: false));
  }

  void submit(String songId) async {
    if (await _isOffline()) return;
    unawaited(_api.scrobble(songId, submission: true));
  }
}
