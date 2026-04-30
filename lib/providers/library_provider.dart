import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'settings_provider.dart';
import '../database/app_database.dart';
import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Metadata Caching helpers (using AppDatabase/Drift)
// ---------------------------------------------------------------------------

Future<void> _cacheSongs(AppDatabase db, List<Song> songs) async {
  await db.batch((batch) {
    for (final song in songs) {
      batch.insert(
        db.songMetadata,
        SongMetadataCompanion.insert(
          songId: song.id,
          trackName: song.title,
          artistName: song.artist,
          albumName: song.album,
          durationSec: song.duration,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          genre: Value(song.genre),
          composer: Value(song.composer),
          year: Value(song.year),
          playCount: Value(song.playCount),
          rating: Value(song.rating),
          starred: Value(song.starred),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  });
}

Future<List<Song>> _getCachedSongs(AppDatabase db) async {
  final rows = await db.select(db.songMetadata).get();
  return rows.map((r) => Song(
    id: r.songId,
    title: r.trackName,
    artist: r.artistName,
    album: r.albumName,
    duration: r.durationSec,
    genre: r.genre ?? '',
    composer: r.composer ?? '',
    coverArt: '',
    track: 0,
    year: r.year ?? 0,
    playCount: r.playCount,
    rating: r.rating,
    starred: r.starred,
  )).toList();
}

enum LibraryFilter { allSongs, playlists, albums, downloaded }

final libraryFilterProvider = StateProvider<LibraryFilter>((ref) => LibraryFilter.allSongs);

final recentlyPlayedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getRecentlyPlayedAlbums();
});

final frequentAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getFrequentAlbums();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getPlaylists();
});

final favoritesProvider = FutureProvider<({List<Song> songs, List<Album> albums})>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return (songs: <Song>[], albums: <Album>[]);
  final service = ref.watch(subsonicServiceProvider);
  return service.getStarred();
});

final allSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];

  final db = ref.watch(appDatabaseProvider);
  final service = ref.watch(subsonicServiceProvider);

  final cached = await _getCachedSongs(db);
  if (cached.isNotEmpty) {
    service.getAllSongs(size: 5000).then((fresh) async {
      final sorted = await compute(_sortSongsByCreated, fresh);
      await _cacheSongs(db, sorted);
    });
    return compute(_sortSongsByCreated, cached);
  }

  final songs = await service.getAllSongs(size: 5000);
  final sorted = await compute(_sortSongsByCreated, songs);
  await _cacheSongs(db, sorted);
  return sorted;
});

final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getAlbums(size: 1000);
});

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

List<Song> _sortSongsByCreated(List<Song> songs) {
  songs.sort((a, b) {
    if (a.created == null && b.created == null) return 0;
    if (a.created == null) return 1;
    if (b.created == null) return -1;
    return b.created!.compareTo(a.created!);
  });
  return songs;
}
