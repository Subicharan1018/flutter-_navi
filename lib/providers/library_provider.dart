import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'settings_provider.dart';

enum LibraryFilter { allSongs, playlists, albums, downloaded }

final libraryFilterProvider = StateProvider<LibraryFilter>((ref) => LibraryFilter.allSongs);

final recentlyPlayedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final service = ref.watch(subsonicServiceProvider);
  return await service.getRecentlyPlayedAlbums();
});

final frequentAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final service = ref.watch(subsonicServiceProvider);
  return await service.getFrequentAlbums();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final service = ref.watch(subsonicServiceProvider);
  return await service.getPlaylists();
});

final allSongsProvider = FutureProvider<List<Song>>((ref) async {
  final service = ref.watch(subsonicServiceProvider);
  final songs = await service.getAllSongs(size: 5000);

  // Sort by created date descending (newest first)
  songs.sort((a, b) {
    if (a.created == null && b.created == null) return 0;
    if (a.created == null) return 1;
    if (b.created == null) return -1;
    return b.created!.compareTo(a.created!);
  });

  return songs;
});

final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final service = ref.watch(subsonicServiceProvider);
  return await service.getAlbums(size: 1000);
});

// Helper provider to get filtered content
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
