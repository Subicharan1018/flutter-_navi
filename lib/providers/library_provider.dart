import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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

/// Looks up a cached song's cover art URL by title and artist.
/// Returns null if not found in the local database.
final songCoverUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length < 2) return null;
  final title = parts[0];
  final artist = parts[1];

  final db = ref.watch(appDatabaseProvider);

  // Try exact match first
  var match = await (db.select(db.songMetadata)
        ..where((t) => t.trackName.equals(title) & t.artistName.equals(artist))
        ..limit(1))
      .getSingleOrNull();

  // Fallback to title-only match if exact match fails
  match ??= await (db.select(db.songMetadata)
        ..where((t) => t.trackName.equals(title))
        ..limit(1))
      .getSingleOrNull();

  if (match != null) {
    final coverId = match.songId;
    return ref.read(subsonicServiceProvider).getCoverArtUrl(coverId);
  }
  return null;
});

/// Looks up a cover art URL to represent an *artist*, by finding any cached
/// song of theirs. Artists have no portrait in the Subsonic metadata we cache,
/// so their most-recently-cached cover stands in — real artwork from their own
/// catalogue rather than a synthesised placeholder.
final artistCoverUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, artist) async {
  if (artist.isEmpty) return null;

  final db = ref.watch(appDatabaseProvider);

  final match = await (db.select(db.songMetadata)
        ..where((t) => t.artistName.equals(artist))
        ..limit(1))
      .getSingleOrNull();

  if (match == null) return null;
  return ref.read(subsonicServiceProvider).getCoverArtUrl(match.songId);
});


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
          createdAt: Value(song.created?.millisecondsSinceEpoch),
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
          created: r.createdAt != null
              ? DateTime.fromMillisecondsSinceEpoch(r.createdAt!)
              : null,
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
    error: (_, _) => false,
    loading: () => false,
  );
});

/// Wraps [allSongsProvider] and filters to downloaded-only when offline.
/// When online, returns the full song list unchanged.
final offlineAwareSongsProvider = Provider.autoDispose<AsyncValue<List<Song>>>((ref) {
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

// MEM-OPT: Changed from keepAlive to autoDispose. The home screen data is
// released when the user navigates away, preventing permanent retention.
final recentlyPlayedAlbumsProvider = FutureProvider.autoDispose<List<Album>>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getRecentlyPlayedAlbums();
});

/// Recently played unique tracks, sourced from the local Drift DB.
/// Joins play_events with song_metadata, ordered by tsStart DESC,
/// deduplicates by songId, and returns at most 30 results.
final recentlyPlayedSongsProvider = FutureProvider<List<Song>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  // Fetch the 150 most-recent play events so we can de-duplicate by songId
  // down to 30 distinct tracks without a complex SQL window query.
  final events = await (db.select(db.playEvents)
        ..orderBy([(t) => OrderingTerm.desc(t.tsStart)])
        ..limit(150))
      .get();

  final seenIds = <String>{};
  final uniqueIds = <String>[];
  for (final e in events) {
    if (seenIds.add(e.songId)) {
      uniqueIds.add(e.songId);
      if (uniqueIds.length >= 30) break;
    }
  }
  if (uniqueIds.isEmpty) return [];

  final metaRows = await (db.select(db.songMetadata)
        ..where((t) => t.songId.isIn(uniqueIds)))
      .get();

  // Build a lookup by songId for O(1) access
  final metaById = {for (final r in metaRows) r.songId: r};

  // Return songs in the same order as uniqueIds (most-recently-played first)
  final songs = <Song>[];
  for (final id in uniqueIds) {
    final meta = metaById[id];
    if (meta == null) continue;
    songs.add(
      Song(
        id: meta.songId,
        title: meta.trackName,
        artist: meta.artistName,
        album: meta.albumName,
        duration: meta.durationSec,
        genre: meta.genre ?? '',
        composer: meta.composer ?? '',
        coverArt: meta.songId, // Subsonic uses songId as the cover art key
        track: 0,
        year: meta.year ?? 0,
        playCount: meta.playCount,
        rating: meta.rating,
        starred: meta.starred,
      ),
    );
  }
  return songs;
});

// MEM-OPT: autoDispose — released when home screen is popped.
final frequentAlbumsProvider = FutureProvider.autoDispose<List<Album>>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];
  final service = ref.watch(subsonicServiceProvider);
  return service.getFrequentAlbums();
});

// MEM-OPT: autoDispose — released when the playlists tab is closed.
final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
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

// MEM-OPT: autoDispose — favorites screen data is only needed when that
// screen is visible. Released when the screen is popped.
final favoritesProvider =
    FutureProvider.autoDispose<({List<Song> songs, List<Album> albums})>((ref) async {
      final settings = ref.watch(settingsProvider);
      if (settings.serverUrl.isEmpty || settings.password.isEmpty) {
        return (songs: <Song>[], albums: <Album>[]);
      }
      final service = ref.watch(subsonicServiceProvider);
      return service.getStarred();
    });

DateTime? _lastRefreshTime;

final allSongsProvider = FutureProvider.autoDispose<List<Song>>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return [];

  final db = ref.watch(appDatabaseProvider);
  final service = ref.watch(subsonicServiceProvider);

  Future<void> fetchAndSyncSongs() async {
    const chunkSize = 500;
    int offset = 0;
    while (true) {
      final chunk = await service.getAllSongs(size: chunkSize, offset: offset);
      if (chunk.isEmpty) break;
      await _cacheSongs(db, chunk);
      if (chunk.length < chunkSize) break;
      offset += chunkSize;
    }
  }

  final cached = await _getCachedSongs(db);
  final now = DateTime.now();
  final shouldRefresh = _lastRefreshTime == null ||
      now.difference(_lastRefreshTime!) > const Duration(minutes: 5);

  if (cached.isNotEmpty) {
    if (shouldRefresh) {
      _lastRefreshTime = now;
      fetchAndSyncSongs()
          .then((_) {
            ref.invalidateSelf();
          })
          .catchError((_) {
            // Background refresh failed — stale cache is still valid.
          });
    }
    _sortSongsByCreated(cached);
    return cached;
  }

  await fetchAndSyncSongs();
  _lastRefreshTime = DateTime.now();
  final fresh = await _getCachedSongs(db);
  _sortSongsByCreated(fresh);
  return fresh;
});

// MEM-OPT: autoDispose — library albums only held while the albums tab is open.
final libraryAlbumsProvider = FutureProvider.autoDispose<List<Album>>((ref) async {
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
    extends Notifier<Map<LibraryFilter, LibrarySortPreference>> {
  @override
  Map<LibraryFilter, LibrarySortPreference> build() {
    return _restore();
  }

  void setSort(LibraryFilter section, LibrarySortField field) {
    final current = state[section] ?? const LibrarySortPreference();
    final next = current.toggleField(field);
    state = {...state, section: next};
    _persist(section, next);
  }

  Map<LibraryFilter, LibrarySortPreference> _restore() {
    // Guard: prefs box must be open. Safe in production (HiveBoxes.init()
    // completes at main.dart:17 before runApp at main.dart:44), but protects
    // against test environments and hot-restart races.
    if (!Hive.isBoxOpen('prefs')) return const {};
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
    return restored;
  }

  void _persist(LibraryFilter section, LibrarySortPreference pref) {
    final box = HiveBoxes.prefs;
    box.put(pref.fieldHiveKey(section.name), pref.field.index);
    box.put(pref.dirHiveKey(section.name), pref.direction.index);
  }
}

final librarySortProvider =
    NotifierProvider<
      LibrarySortNotifier,
      Map<LibraryFilter, LibrarySortPreference>
    >(LibrarySortNotifier.new);

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

// ---------------------------------------------------------------------------
// Paginated local database query pagination
// ---------------------------------------------------------------------------

final downloadedSongIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final downloadState = ref.watch(downloadStateProvider);
  return downloadState.entries
      .where((e) => e.value.status == SongDownloadStatus.downloaded)
      .map((e) => e.key)
      .toSet();
});

class PaginatedSongsParam {
  final LibraryFilter filter;
  final String searchQuery;

  const PaginatedSongsParam({
    required this.filter,
    required this.searchQuery,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaginatedSongsParam &&
          runtimeType == other.runtimeType &&
          filter == other.filter &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode => Object.hash(filter, searchQuery);
}

class PaginatedSongsState {
  final List<Song> songs;
  final bool hasMore;
  final bool isLoadingMore;
  final int offset;

  const PaginatedSongsState({
    required this.songs,
    required this.hasMore,
    required this.isLoadingMore,
    required this.offset,
  });

  PaginatedSongsState copyWith({
    List<Song>? songs,
    bool? hasMore,
    bool? isLoadingMore,
    int? offset,
  }) {
    return PaginatedSongsState(
      songs: songs ?? this.songs,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      offset: offset ?? this.offset,
    );
  }
}

class PaginatedSongsNotifier extends StateNotifier<PaginatedSongsState> {
  final Ref ref;
  final PaginatedSongsParam arg;
  static const int pageSize = 50;

  PaginatedSongsNotifier(this.ref, this.arg)
      : super(const PaginatedSongsState(
          songs: [],
          hasMore: true,
          isLoadingMore: false,
          offset: 0,
        )) {
    ref.listen(librarySortProvider, (prev, next) {
      loadNextPage(isRefresh: true);
    });
    ref.listen(isOfflineProvider, (prev, next) {
      loadNextPage(isRefresh: true);
    });
    if (arg.filter == LibraryFilter.downloaded || ref.read(isOfflineProvider)) {
      ref.listen(downloadedSongIdsProvider, (prev, next) {
        loadNextPage(isRefresh: true);
      });
    }

    // Schedule initial load
    Future.microtask(() => loadNextPage(isRefresh: true));
  }

  Future<void> loadNextPage({bool isRefresh = false}) async {
    if (state.isLoadingMore || (!state.hasMore && !isRefresh)) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final db = ref.read(appDatabaseProvider);
      final sortPrefs = ref.read(librarySortProvider);
      final isOffline = ref.read(isOfflineProvider);
      
      final effectiveFilter = arg.filter == LibraryFilter.downloaded
          ? LibraryFilter.allSongs
          : arg.filter;
      final pref = sortPrefs[effectiveFilter] ?? const LibrarySortPreference();

      final currentOffset = isRefresh ? 0 : state.offset;
      final query = db.select(db.songMetadata);

      if (arg.searchQuery.isNotEmpty) {
        query.where((t) =>
            t.trackName.like('%${arg.searchQuery}%') |
            t.artistName.like('%${arg.searchQuery}%'));
      }

      if (arg.filter == LibraryFilter.downloaded || isOffline) {
        final downloadedIds = ref.read(downloadedSongIdsProvider);
        if (downloadedIds.isEmpty) {
          state = state.copyWith(
            songs: isRefresh ? [] : state.songs,
            hasMore: false,
            isLoadingMore: false,
            offset: currentOffset,
          );
          return;
        }
        query.where((t) => t.songId.isIn(downloadedIds.toList()));
      }

      query.orderBy([
        (t) {
          final expr = _getSortExpression(t, pref.field);
          return OrderingTerm(
            expression: expr,
            mode: pref.direction == LibrarySortDirection.asc
                ? OrderingMode.asc
                : OrderingMode.desc,
          );
        }
      ]);

      query.limit(pageSize, offset: currentOffset);

      final rows = await query.get();

      final newSongs = rows.map((r) => Song(
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
        created: r.createdAt != null
            ? DateTime.fromMillisecondsSinceEpoch(r.createdAt!)
            : null,
      )).toList();

      final hasMore = newSongs.length == pageSize;
      final nextOffset = currentOffset + newSongs.length;

      state = state.copyWith(
        songs: isRefresh ? newSongs : [...state.songs, ...newSongs],
        hasMore: hasMore,
        isLoadingMore: false,
        offset: nextOffset,
      );
    } catch (e, stack) {
      debugPrint('[PaginatedSongsNotifier] Error loading page: $e\n$stack');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Expression<Object> _getSortExpression(dynamic table, LibrarySortField field) {
    switch (field) {
      case LibrarySortField.name:
        return table.trackName;
      case LibrarySortField.recentlyAdded:
        return table.createdAt;
      case LibrarySortField.playCount:
        return table.playCount;
      case LibrarySortField.duration:
        return table.durationSec;
      case LibrarySortField.artistName:
        return table.artistName;
    }
  }
}

final paginatedSongsProvider = StateNotifierProvider.autoDispose
    .family<PaginatedSongsNotifier, PaginatedSongsState, PaginatedSongsParam>(
  (ref, arg) => PaginatedSongsNotifier(ref, arg),
);
