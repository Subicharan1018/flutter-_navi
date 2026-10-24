import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/playlist.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';

/// What turning a downloaded playlist into the user's own playlist needs from
/// the music server. Calls go out with the user's own Subsonic login, so the
/// playlist belongs to them (tg-fetcher only has an admin login).
abstract class FetchPlaylistStore {
  /// The signed-in username.
  String get user;
  Future<List<Playlist>> playlists();
  Future<List<String>> songIds(String playlistId);
  Future<String> create(String name);
  Future<void> setSongs(String playlistId, List<String> songIds);
}

class SubsonicPlaylistStore implements FetchPlaylistStore {
  final Ref ref;
  SubsonicPlaylistStore(this.ref);

  @override
  String get user => ref.read(settingsProvider).username;

  @override
  Future<List<Playlist>> playlists() => ref.read(subsonicServiceProvider).getPlaylists();

  @override
  Future<List<String>> songIds(String playlistId) async => [
        for (final s in await ref.read(subsonicServiceProvider).getPlaylistSongs(playlistId, forceRefresh: true)) s.id,
      ];

  @override
  Future<String> create(String name) async => (await ref.read(playlistControllerProvider).create(name)).id;

  @override
  Future<void> setSongs(String playlistId, List<String> songIds) async {
    await ref.read(subsonicServiceProvider).setPlaylistSongs(playlistId, songIds);
    ref.invalidate(songsInPlaylistProvider(playlistId));
    ref.invalidate(playlistsProvider);
  }
}

final fetchPlaylistStoreProvider = Provider<FetchPlaylistStore>(SubsonicPlaylistStore.new);

/// Makes the user's playlist [name] with [songIds] in order, or — when the
/// user already has a playlist of that name (the same bot playlist asked for
/// again) — adds only the songs it doesn't have yet, at the end. Never makes
/// a copy, and never touches another user's playlist of the same name.
/// Returns the playlist id.
Future<String> upsertFetchPlaylist(FetchPlaylistStore store, String name, List<String> songIds) async {
  final user = store.user.toLowerCase();
  final mine = (await store.playlists())
      .where((p) => p.name == name && (p.owner == null || p.owner!.toLowerCase() == user))
      .firstOrNull;
  final wanted = songIds.toSet().toList();      // each song once, first position wins
  if (mine == null) {
    final id = await store.create(name);
    if (wanted.isNotEmpty) await store.setSongs(id, wanted);
    return id;
  }
  final current = await store.songIds(mine.id);
  final have = current.toSet();
  final fresh = [for (final id in wanted) if (!have.contains(id)) id];
  if (fresh.isNotEmpty) await store.setSongs(mine.id, [...current, ...fresh]);
  return mine.id;
}
