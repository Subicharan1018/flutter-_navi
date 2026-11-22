import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import '../../models/song.dart';
import 'playlist_versions.dart';

abstract class PlaylistVersionsBackend {
  String? read();
  Future<void> write(String value);
}

class HivePlaylistVersionsBackend implements PlaylistVersionsBackend {
  static const key = 'playlistVersions_v1';

  @override
  String? read() {
    final v = HiveBoxes.prefs.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String value) => HiveBoxes.prefs.put(key, value);
}

final playlistVersionsBackendProvider = Provider<PlaylistVersionsBackend>((ref) => HivePlaylistVersionsBackend());

/// Most playlists remembered; the least recently changed are dropped past it.
const playlistsWithHistory = 60;

class PlaylistVersionsNotifier extends Notifier<Map<String, List<PlaylistVersion>>> {
  @override
  Map<String, List<PlaylistVersion>> build() {
    try {
      return PlaylistVersions.decode(ref.read(playlistVersionsBackendProvider).read());
    } catch (_) {
      return {};
    }
  }

  /// Records the playlist as seen now. A no-op when nothing changed since the
  /// last snapshot.
  void record(String playlistId, List<Song> songs, {DateTime? now}) {
    final before = state[playlistId] ?? const <PlaylistVersion>[];
    final after = PlaylistVersions.record(before, songs, now ?? DateTime.now());
    if (identical(before, after)) return;
    final next = {...state, playlistId: after};
    // Keep the most recently changed playlists only.
    if (next.length > playlistsWithHistory) {
      final byRecent = next.entries.toList()..sort((a, b) => b.value.first.at.compareTo(a.value.first.at));
      next
        ..clear()
        ..addEntries(byRecent.take(playlistsWithHistory));
    }
    state = next;
    try {
      ref.read(playlistVersionsBackendProvider).write(PlaylistVersions.encode(state));
    } catch (_) {}
  }

  void forget(String playlistId) {
    if (!state.containsKey(playlistId)) return;
    state = {...state}..remove(playlistId);
    try {
      ref.read(playlistVersionsBackendProvider).write(PlaylistVersions.encode(state));
    } catch (_) {}
  }
}

final playlistVersionsProvider =
    NotifierProvider<PlaylistVersionsNotifier, Map<String, List<PlaylistVersion>>>(PlaylistVersionsNotifier.new);
