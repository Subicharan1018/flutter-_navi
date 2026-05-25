import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/album.dart';
import '../models/library_sort.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'settings_provider.dart';
import 'download_provider.dart';
import '../models/download_state.dart';
import '../database/app_database.dart';
import '../core/hive_boxes.dart';
import 'package:drift/drift.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

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
  return rows
      .map(
        (r) => Song(
          id: r.songId,
          title: r.trackName,
          artist: r.artistName,
          album: r.albumName,
          duration: r.durationSec,
          genre: r.genre ?? '',
          composer: r.composer ?? '',
          coverArt: r.songId,
          track: 0,
          year: r.year ?? 0,
          playCount: r.playCount,
          rating: r.rating,
          starred: r.starred,
        ),
      )
      .toList();
}

enum LibraryFilter { allSongs, playlists, albums, downloaded }

final libraryFilterProvider = StateProvider<LibraryFilter>(
  (ref) => LibraryFilter.allSongs,
);

// ---------------------------------------------------------------------------
// Connectivity-aware providers (Feature 3: Offline Mode)
// ---------------------------------------------------------------------------

/// Streams connectivity changes from the device radio.
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return Connectivity().onConnectivityChanged;
});

/// Derived boolean — true when the device has no connectivity.
final isOfflineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityStreamProvider);
  return connectivity.when(
    data: (results) => results.contains(ConnectivityResult.none),
    error: (_, __) => false,
    loading: () => false,
  );
});

/// Wraps [allSongsProvider] and filters to downloaded-only when offline.
/// When online, returns the full song list unchanged.
final offlineAwareSongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final isOffline = ref.watch(isOfflineProvider);
  final allSongs = ref.watch(allSongsProvider);

  if (!isOffline) return allSongs;

  // When offline, filter to only downloaded songs.
  final downloadState = ref.watch(downloadStateProvider);
  final downloadedIds = downloadState.entries
      .where((e) => e.value.status == SongDownloadStatus.downloaded)
      .map((e) => e.key)
      .toSet();

  return allSongs.whenData(
    (songs) => songs.where((s) => downloadedIds.contains(s.id)).toList(),
  );
});

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

// ---------------------------------------------------------------------------
// FIX (Bug 1 + Bug 3):
//
// Previously: FutureProvider.family (kept alive forever, no forceRefresh)
//   → After ref.invalidate(), getPlaylistSongs() hit the SQLite stale-while-
//     revalidate path and returned the old cached list immediately, so the
//     checkmark never changed.
//
// Now: autoDispose.family + forceRefresh: true
//   → autoDispose drops the provider when the dialog closes, so reopening
//     always gets a fresh fetch. forceRefresh: true skips the SQLite cache
//     entirely so the network result is always authoritative.
//   → The dialog's Consumer widgets see a real loading → data transition after
//     each toggle, giving correct checkmarks.
// ---------------------------------------------------------------------------
final songsInPlaylistProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, playlistId) async {
      final service = ref.watch(subsonicServiceProvider);
      // Always fetch from network — stale cache must never win here because this
      // provider is the source of truth for the "is this song already added?"
      // membership check in AddToPlaylistDialog.
      return service.getPlaylistSongs(playlistId, forceRefresh: true);
    });

final favoritesProvider =
    FutureProvider<({List<Song> songs, List<Album> albums})>((ref) async {
      ref.keepAlive();
      final settings = ref.watch(settingsProvider);
      if (settings.serverUrl.isEmpty || settings.password.isEmpty) {
        return (songs: <Song>[], albums: <Album>[]);
      }
      final service = ref.watch(subsonicServiceProvider);
      return service.getStarred();
    });

final allSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.keepAlive();
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];

  final db = ref.watch(appDatabaseProvider);
  final service = ref.watch(subsonicServiceProvider);

  Future<List<Song>> fetchAllSongsPaginated() async {
    final allSongs = <Song>[];
    const chunkSize = 500;
    int offset = 0;
    while (true) {
      final chunk = await service.getAllSongs(size: chunkSize, offset: offset);
      if (chunk.isEmpty) break;
      allSongs.addAll(chunk);
      if (chunk.length < chunkSize) break;
      offset += chunkSize;
    }
    return allSongs;
  }

  final cached = await _getCachedSongs(db);
  if (cached.isNotEmpty) {
    // RC-5 FIX: After background refresh, invalidate this provider so the
    // UI gets fresh data. Previously the fire-and-forget .then() updated the
    // SQLite cache but never re-emitted to Riverpod, leaving stale data
    // visible for the entire session.
    fetchAllSongsPaginated()
        .then((fresh) async {
          final sorted = await compute(_sortSongsByCreated, fresh);
          await _cacheSongs(db, sorted);
          // Trigger a provider re-fetch with the fresh cached data.
          ref.invalidateSelf();
        })
        .catchError((_) {
          // Background refresh failed — stale cache is still valid.
        });
    return compute(_sortSongsByCreated, cached);
  }

  final songs = await fetchAllSongsPaginated();
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
      // Use offline-aware provider: filters to downloaded-only when offline.
      return ref.watch(offlineAwareSongsProvider);
    case LibraryFilter.playlists:
      return ref.watch(playlistsProvider);
    case LibraryFilter.albums:
      return ref.watch(libraryAlbumsProvider);
    case LibraryFilter.downloaded:
      // Show downloaded songs explicitly when the user picks this filter.
      final downloadState = ref.watch(downloadStateProvider);
      final downloadedIds = downloadState.entries
          .where((e) => e.value.status == SongDownloadStatus.downloaded)
          .map((e) => e.key)
          .toSet();
      return ref
          .watch(allSongsProvider)
          .whenData(
            (songs) =>
                songs.where((s) => downloadedIds.contains(s.id)).toList(),
          );
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

// ---------------------------------------------------------------------------
// Sort comparators (pure top-level functions — safe to call from isolates)
// ---------------------------------------------------------------------------

int _compareDatesAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // nulls sort last
  if (b == null) return -1;
  return a.compareTo(b);
}

int _sortCompareSong(Song a, Song b, LibrarySortPreference pref) {
  final cmp = switch (pref.field) {
    LibrarySortField.name => a.title.toLowerCase().compareTo(
      b.title.toLowerCase(),
    ),
    LibrarySortField.recentlyAdded => _compareDatesAsc(a.created, b.created),
    LibrarySortField.playCount => a.playCount.compareTo(b.playCount),
    LibrarySortField.duration => a.duration.compareTo(b.duration),
    LibrarySortField.artistName => a.artist.toLowerCase().compareTo(
      b.artist.toLowerCase(),
    ),
  };
  return pref.direction == LibrarySortDirection.asc ? cmp : -cmp;
}

int _sortCompareAlbum(Album a, Album b, LibrarySortPreference pref) {
  final cmp = switch (pref.field) {
    LibrarySortField.name => a.name.toLowerCase().compareTo(
      b.name.toLowerCase(),
    ),
    LibrarySortField.recentlyAdded => 0, // Albums have no creation date
    LibrarySortField.playCount => 0, // Albums have no play count
    LibrarySortField.duration => a.duration.compareTo(b.duration),
    LibrarySortField.artistName => a.artist.toLowerCase().compareTo(
      b.artist.toLowerCase(),
    ),
  };
  return pref.direction == LibrarySortDirection.asc ? cmp : -cmp;
}

int _sortComparePlaylist(Playlist a, Playlist b, LibrarySortPreference pref) {
  final cmp = switch (pref.field) {
    LibrarySortField.name => a.name.toLowerCase().compareTo(
      b.name.toLowerCase(),
    ),
    // Playlists have no creation date, play count, duration, or artist field.
    LibrarySortField.recentlyAdded => 0,
    LibrarySortField.playCount => 0,
    LibrarySortField.duration => 0,
    LibrarySortField.artistName => 0,
  };
  return pref.direction == LibrarySortDirection.asc ? cmp : -cmp;
}

// ---------------------------------------------------------------------------
// LibrarySortNotifier — per-section sort state, persisted to Hive prefs box
// ---------------------------------------------------------------------------

class LibrarySortNotifier
    extends StateNotifier<Map<LibraryFilter, LibrarySortPreference>> {
  LibrarySortNotifier() : super(const {}) {
    _restore();
  }

  void setSort(LibraryFilter section, LibrarySortField field) {
    final current = state[section] ?? const LibrarySortPreference();
    final next = current.toggleField(field);
    state = {...state, section: next};
    _persist(section, next);
  }

  void _restore() {
    // Guard: prefs box must be open. Safe in production (HiveBoxes.init()
    // completes at main.dart:17 before runApp at main.dart:44), but protects
    // against test environments and hot-restart races.
    if (!Hive.isBoxOpen('prefs')) return;
    final restored = <LibraryFilter, LibrarySortPreference>{};
    final box = HiveBoxes.prefs;
    for (final section in LibraryFilter.values) {
      final dummy = const LibrarySortPreference();
      final fi = box.get(dummy.fieldHiveKey(section.name));
      final di = box.get(dummy.dirHiveKey(section.name));
      restored[section] = LibrarySortPreference(
        field: fi != null
            ? LibrarySortField.values[(fi as int).clamp(
                0,
                LibrarySortField.values.length - 1,
              )]
            : LibrarySortField.name,
        direction: di != null
            ? LibrarySortDirection.values[(di as int).clamp(
                0,
                LibrarySortDirection.values.length - 1,
              )]
            : LibrarySortDirection.asc,
      );
    }
    state = restored;
  }

  void _persist(LibraryFilter section, LibrarySortPreference pref) {
    final box = HiveBoxes.prefs;
    box.put(pref.fieldHiveKey(section.name), pref.field.index);
    box.put(pref.dirHiveKey(section.name), pref.direction.index);
  }
}

final librarySortProvider =
    StateNotifierProvider<
      LibrarySortNotifier,
      Map<LibraryFilter, LibrarySortPreference>
    >((_) => LibrarySortNotifier());

// ---------------------------------------------------------------------------
// Typed sorted providers
// Each wraps its corresponding data provider and applies the active sort pref.
// The `downloaded` filter re-uses the `allSongs` sort key explicitly.
// ---------------------------------------------------------------------------

/// Sorted songs — used by allSongs and downloaded tabs.
/// The caller is responsible for passing the correctly-filtered song list via
/// [offlineAwareSongsProvider] (allSongs) or the downloaded filter (downloaded).
final sortedSongsProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final sortPrefs = ref.watch(librarySortProvider);
  final filter = ref.watch(libraryFilterProvider);
  // downloaded has no own key — explicitly falls back to allSongs pref
  final effectiveSection = filter == LibraryFilter.downloaded
      ? LibraryFilter.allSongs
      : filter;
  final pref = sortPrefs[effectiveSection] ?? const LibrarySortPreference();

  final AsyncValue<List<Song>> source;
  if (filter == LibraryFilter.downloaded) {
    final downloadState = ref.watch(downloadStateProvider);
    final downloadedIds = downloadState.entries
        .where((e) => e.value.status == SongDownloadStatus.downloaded)
        .map((e) => e.key)
        .toSet();
    source = ref
        .watch(allSongsProvider)
        .whenData(
          (s) => s.where((song) => downloadedIds.contains(song.id)).toList(),
        );
  } else {
    source = ref.watch(offlineAwareSongsProvider);
  }

  return source.whenData((songs) {
    final sorted = [...songs]..sort((a, b) => _sortCompareSong(a, b, pref));
    return sorted;
  });
});

/// Sorted albums.
final sortedAlbumsProvider = Provider<AsyncValue<List<Album>>>((ref) {
  final sortPrefs = ref.watch(librarySortProvider);
  final pref = sortPrefs[LibraryFilter.albums] ?? const LibrarySortPreference();
  return ref.watch(libraryAlbumsProvider).whenData((albums) {
    final sorted = [...albums]..sort((a, b) => _sortCompareAlbum(a, b, pref));
    return sorted;
  });
});

/// Sorted playlists.
final sortedPlaylistsProvider = Provider<AsyncValue<List<Playlist>>>((ref) {
  final sortPrefs = ref.watch(librarySortProvider);
  final pref =
      sortPrefs[LibraryFilter.playlists] ?? const LibrarySortPreference();
  return ref.watch(playlistsProvider).whenData((playlists) {
    final sorted = [...playlists]
      ..sort((a, b) => _sortComparePlaylist(a, b, pref));
    return sorted;
  });
});

// ---------------------------------------------------------------------------
// Playlist Actions Controller
// ---------------------------------------------------------------------------
class PlaylistController {
  final Ref ref;
  PlaylistController(this.ref);

  Future<void> createAndAdd(String name, String songId) async {
    final service = ref.read(subsonicServiceProvider);
    await service.createPlaylist(name);

    ref.invalidate(playlistsProvider);
    final playlists = await ref.read(playlistsProvider.future);

    final newPlaylist = playlists.firstWhere(
      (p) => p.name == name,
      orElse: () => throw Exception('Playlist not found after creation'),
    );
    await service.updatePlaylist(newPlaylist.id, songIdToAdd: songId);

    ref.invalidate(songsInPlaylistProvider(newPlaylist.id));
  }

  Future<int> batchUpdate({
    required String songId,
    required Set<String> adds,
    required Set<String> removes,
  }) async {
    final service = ref.read(subsonicServiceProvider);
    int successCount = 0;

    for (final playlistId in adds) {
      await service.updatePlaylist(playlistId, songIdToAdd: songId);
      ref.invalidate(songsInPlaylistProvider(playlistId));
      successCount++;
    }
    for (final playlistId in removes) {
      final freshSongs = await service.getPlaylistSongs(
        playlistId,
        forceRefresh: true,
      );
      final serverIndex = freshSongs.indexWhere((s) => s.id == songId);
      if (serverIndex >= 0) {
        await service.updatePlaylist(
          playlistId,
          songIndexToRemove: serverIndex,
        );
      }
      ref.invalidate(songsInPlaylistProvider(playlistId));
      successCount++;
    }
    return successCount;
  }
}

final playlistControllerProvider = Provider((ref) => PlaylistController(ref));
