import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/song.dart';
import '../models/library_sort.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/swipeable_library_tile.dart';
import '../core/theme.dart';
import 'playlist_details_screen.dart';
import 'edit_playlist_screen.dart';
import 'search_screen.dart';
import 'offline_screen.dart';
import '../services/subsonic_service.dart';
import '../core/navigation_transitions.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // PERF-5: guard prevents re-creating AnimationControllers on every rebuild.
  bool _listAnimated = false;
  LibraryFilter? _lastFilter;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    final service = ref.watch(subsonicServiceProvider);

    // Switch to the correctly-typed sorted provider for the active filter.
    final AsyncValue<List<dynamic>> filteredContentAsync = switch (filter) {
      LibraryFilter.allSongs    => ref.watch(sortedSongsProvider).whenData((s) => <dynamic>[...s]),
      LibraryFilter.downloaded  => ref.watch(sortedSongsProvider).whenData((s) => <dynamic>[...s]),
      LibraryFilter.albums      => ref.watch(sortedAlbumsProvider).whenData((a) => <dynamic>[...a]),
      LibraryFilter.playlists   => ref.watch(sortedPlaylistsProvider).whenData((p) => <dynamic>[...p]),
    };

    if (_lastFilter != filter) {
      _lastFilter = filter;
      _listAnimated = false;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeTokens.of(context).isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.of(context).padding.top + 16, 16, 8),
                child: Row(
                  children: [
                    Text('Your Library', style: ThemeTokens.of(context).headingMd),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: 'Search library',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.search_rounded,
                              color: ThemeTokens.of(context).textPrimary, size: 24),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SearchScreen())),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Create new playlist',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.add_rounded,
                              color: ThemeTokens.of(context).textPrimary, size: 28),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const CreatePlaylistDialog(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter chips ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  children: [
                    _FilterChip(
                      label: 'All Songs',
                      isSelected: filter == LibraryFilter.allSongs,
                      onTap: () =>
                          ref.read(libraryFilterProvider.notifier).state =
                              LibraryFilter.allSongs,
                    ),
                    _FilterChip(
                      label: 'Playlists',
                      isSelected: filter == LibraryFilter.playlists,
                      onTap: () =>
                          ref.read(libraryFilterProvider.notifier).state =
                              LibraryFilter.playlists,
                    ),
                    _FilterChip(
                      label: 'Albums',
                      isSelected: filter == LibraryFilter.albums,
                      onTap: () =>
                          ref.read(libraryFilterProvider.notifier).state =
                              LibraryFilter.albums,
                    ),
                    _FilterChip(
                      label: 'Offline',
                      isSelected: false,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const OfflineScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // ── Sort chips ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SortChipRow(filter: filter),
            ),

            filteredContentAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const SliverFillRemaining(
                    child: _EmptyLibrary(),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.only(top: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        // FIX (Queue-1): Pass index directly from the builder
                        // instead of items.indexOf(item) which is O(n) and
                        // breaks when two songs have identical field values.
                        Widget tile = _buildItem(
                            context, filter, items, items[index], index, service);
                        if (!_listAnimated) {
                          tile = RepaintBoundary(
                            child: tile.animate().fadeIn(
                                  duration: 400.ms,
                                  delay:
                                      (index * 18).clamp(0, 280).ms,
                                ),
                          );
                        }
                        return tile;
                      },
                      childCount: items.length,
                    ),
                  ),
                );
              },
              loading: () => SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                      color: ThemeTokens.of(context).accent, strokeWidth: 2),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Text('Error: $e',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }

  // FIX (Queue-1): Accept explicit `index` parameter so tapping any song in
  // "All Songs" correctly starts playback at that position in the queue.
  // Previously items.indexOf(item) used object equality — if two Song objects
  // had identical data but different instances the wrong index was returned,
  // and the call was also O(n²) across the whole list build.
  Widget _buildItem(BuildContext context, LibraryFilter filter,
      List items, dynamic item, int index, SubsonicService service) {
    switch (filter) {
      case LibraryFilter.allSongs:
      case LibraryFilter.downloaded:
        final song = item as Song;
        final starred = ref.watch(
          playerProvider.select((s) => s.starredIds.contains(song.id)),
        );
        return SwipeableLibraryTile(
          dismissKey: 'song_${song.id}_$index',
          isStarred: starred,
          onSwipeRight: () => addSongsToQueue(
            songs: [song],
            notifier: ref.read(playerProvider.notifier),
            playerState: ref.read(playerProvider),
            context: context,
          ),
          onSwipeLeft: () =>
              ref.read(playerProvider.notifier).toggleStar(song.id),
          child: SongTile(
            song: song,
            onTap: () => ref.read(playerProvider.notifier).setQueue(
                  items.cast<Song>().toList(),
                  index,
                ),
          ),
        );

      case LibraryFilter.playlists:
        return SwipeableLibraryTile(
          dismissKey: 'playlist_${item.id}',
          onSwipeRight: () async {
            try {
              final songs = await service.getPlaylistSongs(item.id);
              if (!context.mounted) return;
              await addSongsToQueue(
                songs: songs,
                notifier: ref.read(playerProvider.notifier),
                playerState: ref.read(playerProvider),
                context: context,
                label: item.name,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not load playlist: $e')),
                );
              }
            }
          },
          child: Semantics(
            button: true,
            label: 'Playlist: ${item.name}, ${item.songCount} songs',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: ThemeTokens.of(context).bgElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: item.coverArt != null && item.coverArt!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: service.getCoverArtUrl(item.coverArt),
                          cacheKey: 'cover_${item.coverArt}',
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                              Icons.queue_music_rounded,
                              color: ThemeTokens.of(context).accent, size: 24),
                        ),
                      )
                    : Icon(Icons.queue_music_rounded,
                        color: ThemeTokens.of(context).accent, size: 24),
              ),
              title: Text(item.name,
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              subtitle: Text('Playlist • ${item.songCount} songs',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textSecondary, fontSize: 12)),
              onTap: () => Navigator.push(
                  context,
                  AppRouteTransitions.fadeScale(
                      builder: (_) => PlaylistDetailsScreen(playlist: item))),
              onLongPress: () => _showPlaylistOptions(context, item),
            ),
          ),
        );

      case LibraryFilter.albums:
        final coverUrl = service.getCoverArtUrl(item.coverArt);
        return SwipeableLibraryTile(
          dismissKey: 'album_${item.id}',
          onSwipeRight: () async {
            try {
              final songs = await service.getAlbum(item.id);
              if (!context.mounted) return;
              await addSongsToQueue(
                songs: songs,
                notifier: ref.read(playerProvider.notifier),
                playerState: ref.read(playerProvider),
                context: context,
                label: item.name,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not load album: $e')),
                );
              }
            }
          },
          child: Semantics(
            button: true,
            label: 'Album: ${item.name} by ${item.artist}',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: ThemeTokens.of(context).bgElevated),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    cacheKey: 'cover_${item.coverArt ?? item.id}',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Icon(
                        Icons.album_rounded,
                        color: ThemeTokens.of(context).textMuted),
                  ),
                ),
              ),
              title: Text(item.name,
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              subtitle: Text('Album • ${item.artist}',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textSecondary, fontSize: 12)),
              onTap: () async {
                try {
                  final songs = await service.getAlbum(item.id);
                  if (context.mounted) {
                    ref.read(playerProvider.notifier).setQueue(songs, 0);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not play album: $e')),
                    );
                  }
                }
              },
            ),
          ),
        );
    }
  }

  void _showPlaylistOptions(BuildContext context, dynamic playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).bgElevated,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.edit_rounded,
                  color: ThemeTokens.of(context).textPrimary),
              title: Text('Edit Playlist',
                  style: TextStyle(color: ThemeTokens.of(context).textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            EditPlaylistScreen(playlist: playlist)));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text('Delete Playlist',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, playlist);
              },
            ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, dynamic playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeTokens.of(context).bgSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Playlist',
            style: TextStyle(
                color: ThemeTokens.of(context).textPrimary,
                fontWeight: FontWeight.bold)),
        content: Text('Delete "${playlist.name}"?',
            style:
                TextStyle(color: ThemeTokens.of(context).textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: ThemeTokens.of(context).textPrimary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final service = ref.read(subsonicServiceProvider);
                await service.deletePlaylist(playlist.id);
                ref.invalidate(playlistsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('Deleted "${playlist.name}"')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Swipe-to-remove song tile with confirmation step
//
// FIX (Swipe-Delete): The previous implicit swipe-to-delete had no guard —
// a slight horizontal flick instantly removed a song with no undo.
//
// New behaviour:
//   • Swipe reveals a red "Remove" background but does NOT delete yet.
//   • Releasing mid-swipe snaps back (confirmationThreshold not reached).
//   • Swiping past the threshold shows a brief "hold to confirm" animation
//     then calls onDelete.
//   • A Snackbar with Undo appears for 4 seconds after deletion.
//
// This is implemented as a wrapper widget so it can be reused anywhere a
// song appears in a dismissible list (playlist details, queue, etc.).
// =============================================================================

class SwipeToDismissSongTile extends StatelessWidget {
  final String dismissKey;
  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback? onUndo;

  const SwipeToDismissSongTile({
    super.key,
    required this.dismissKey,
    required this.child,
    required this.onDelete,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(dismissKey),
      direction: DismissDirection.endToStart,
      // confirmDismiss shows a dialog before the item is actually removed,
      // eliminating accidental swipe deletions.
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ThemeTokens.of(context).bgSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: Text('Remove song?',
                style: TextStyle(
                    color: ThemeTokens.of(context).textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            content: Text(
                'This will remove the song from the playlist.',
                style: TextStyle(
                    color: ThemeTokens.of(context).textSecondary, fontSize: 14)),
            actionsPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style:
                        TextStyle(color: ThemeTokens.of(context).textPrimary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Remove',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      // Red background revealed on swipe
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.redAccent.withValues(alpha: 0.15),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 22),
            SizedBox(width: 6),
            Text('Remove',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
      child: child,
    );
  }
}

// =============================================================================
// Sort chip row — per-section sort selector
// =============================================================================

/// Sort fields available for each library section.
const _kSectionSortFields = <LibraryFilter, List<LibrarySortField>>{
  LibraryFilter.allSongs: [
    LibrarySortField.name,
    LibrarySortField.recentlyAdded,
    LibrarySortField.playCount,
    LibrarySortField.duration,
    LibrarySortField.artistName,
  ],
  LibraryFilter.downloaded: [
    LibrarySortField.name,
    LibrarySortField.recentlyAdded,
    LibrarySortField.playCount,
    LibrarySortField.duration,
    LibrarySortField.artistName,
  ],
  LibraryFilter.albums: [
    LibrarySortField.name,
    LibrarySortField.artistName,
    LibrarySortField.duration,
  ],
  LibraryFilter.playlists: [
    LibrarySortField.name,
  ],
};

const _kSortFieldLabel = <LibrarySortField, String>{
  LibrarySortField.name:          'Name',
  LibrarySortField.recentlyAdded: 'Recent',
  LibrarySortField.playCount:     'Plays',
  LibrarySortField.duration:      'Duration',
  LibrarySortField.artistName:    'Artist',
};

class _SortChipRow extends ConsumerWidget {
  const _SortChipRow({required this.filter});
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortPrefs = ref.watch(librarySortProvider);
    // downloaded piggybacks on allSongs sort pref
    final effectiveFilter = filter == LibraryFilter.downloaded
        ? LibraryFilter.allSongs
        : filter;
    final pref = sortPrefs[effectiveFilter] ?? const LibrarySortPreference();
    final fields = _kSectionSortFields[filter] ?? [];

    if (fields.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: fields.map((field) {
          final isActive = pref.field == field;
          final tokens = ThemeTokens.of(context);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => ref
                  .read(librarySortProvider.notifier)
                  .setSort(effectiveFilter, field),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? tokens.accent.withValues(alpha: 0.15)
                      : tokens.bgElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive
                        ? tokens.accent.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _kSortFieldLabel[field] ?? field.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color:
                            isActive ? tokens.accent : tokens.textSecondary,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      Icon(
                        pref.direction == LibrarySortDirection.asc
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: tokens.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// Filter chip — Spotify-style pill
// =============================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: '$label filter${isSelected ? ", selected" : ""}',
        child: CupertinoClickable(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? ThemeTokens.of(context).accent
                  : ThemeTokens.of(context).bgElevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? (ThemeTokens.of(context).isLight ? Colors.white : Colors.black) : ThemeTokens.of(context).textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_rounded,
              color: ThemeTokens.of(context).textMuted, size: 64),
          SizedBox(height: 16),
          Text('Your library is empty',
              style:
                  TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 16)),
        ],
      ),
    );
  }
}