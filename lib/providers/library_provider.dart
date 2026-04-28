import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'settings_provider.dart';


enum LibraryFilter { allSongs, playlists, albums, downloaded }

final libraryFilterProvider = StateProvider<LibraryFilter>((ref) => LibraryFilter.allSongs);

// ---------------------------------------------------------------------------
// keepAlive() on every heavy network provider so Riverpod never discards the
// fetched data when the widget tree disposes (e.g. tab switch, screen pop).
// Without this the providers re-execute their HTTP request on every visit,
// causing the "loads like a webpage" flash.
// ---------------------------------------------------------------------------

final recentlyPlayedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive(); // ← retain data across widget disposal
  final service = ref.watch(subsonicServiceProvider);
  return await service.getRecentlyPlayedAlbums();
});

final frequentAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive();
  final service = ref.watch(subsonicServiceProvider);
  return await service.getFrequentAlbums();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  ref.keepAlive();
  final service = ref.watch(subsonicServiceProvider);
  return await service.getPlaylists();
});

final allSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.keepAlive(); // 5 000-song list — must never re-fetch on tab switch
  final service = ref.watch(subsonicServiceProvider);
  final songs = await service.getAllSongs(size: 5000);

  // BUG-29: sort 5 000 items on a background isolate instead of the main thread.
  return compute(_sortSongsByCreated, songs);
});

final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive();
  final service = ref.watch(subsonicServiceProvider);
  return await service.getAlbums(size: 1000);
});

/// Derived provider — just reads already-cached async values, no keepAlive needed.
final filteredLibraryProvider = Provider<AsyncValue<List<dynamic>>>((ref) {
  final filter = ref.watch(libraryFilterProvider);

  switch (filter) {
    case LibraryFilter.allSongs:
      return ref.watch(allSongsProvider);
    case LibraryFilter.playlists:
      return ref.watch(playlistsProvider);
    case LibraryFilter.albums:
      return ref.watch(libraryAlbumsProvider);
    case LibraryFilter.downloaded:
      return const AsyncValue.data([]);
  }
});

// ---------------------------------------------------------------------------
// Top-level helper — must be top-level for compute() compatibility
// ---------------------------------------------------------------------------

/// Sorts [songs] by [Song.created] descending on a background isolate (BUG-29).
List<Song> _sortSongsByCreated(List<Song> songs) {
  songs.sort((a, b) {
    if (a.created == null && b.created == null) return 0;
    if (a.created == null) return 1;
    if (b.created == null) return -1;
    return b.created!.compareTo(a.created!);
  });
  return songs;
}