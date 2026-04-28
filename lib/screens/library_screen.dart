import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/create_playlist_dialog.dart';
import '../core/theme.dart';
import 'playlist_details_screen.dart';
import 'edit_playlist_screen.dart';
import 'search_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // PERF-5: Track whether the initial fade-in animation has already played.
  // Without this guard, every filter tap (and every Riverpod rebuild) calls
  // .animate().fadeIn() on every item, re-creating an AnimationController for
  // each of the 5,000 songs in the list.
  bool _listAnimated = false;
  LibraryFilter? _lastFilter;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    final filteredContentAsync = ref.watch(filteredLibraryProvider);

    // Reset animation guard whenever the active filter changes so the newly
    // displayed items get their entrance animation exactly once.
    if (_lastFilter != filter) {
      _lastFilter = filter;
      _listAnimated = false;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.of(context).padding.top + 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Your Library',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.search_rounded,
                          color: Colors.white, size: 24),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const CreatePlaylistDialog(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Filter chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _SpotifyFilterChip(
                      label: 'All Songs',
                      isSelected: filter == LibraryFilter.allSongs,
                      onTap: () => ref
                          .read(libraryFilterProvider.notifier)
                          .state = LibraryFilter.allSongs,
                    ),
                    _SpotifyFilterChip(
                      label: 'Playlists',
                      isSelected: filter == LibraryFilter.playlists,
                      onTap: () => ref
                          .read(libraryFilterProvider.notifier)
                          .state = LibraryFilter.playlists,
                    ),
                    _SpotifyFilterChip(
                      label: 'Albums',
                      isSelected: filter == LibraryFilter.albums,
                      onTap: () => ref
                          .read(libraryFilterProvider.notifier)
                          .state = LibraryFilter.albums,
                    ),
                  ],
                ),
              ),
            ),

            // Content
            filteredContentAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.library_music_rounded,
                              color: AppTheme.textSecondary, size: 64),
                          SizedBox(height: 16),
                          Text('Your library is empty',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 16)),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.only(top: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        Widget tile =
                            _buildLibraryItem(context, filter, items[index]);

                        // PERF-5: Only animate on the first render of each
                        // filter view. Subsequent scrolls/rebuilds skip this
                        // branch entirely, keeping animation controller count at 0.
                        if (!_listAnimated) {
                          tile = tile.animate().fadeIn(
                                duration: 400.ms,
                                delay: (index * 20).clamp(0, 300).ms,
                              );
                          if (index == items.length - 1) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _listAnimated = true);
                            });
                          }
                        }
                        return tile;
                      },
                      childCount: items.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.spotifyGreen)),
              ),
              error: (e, st) => SliverFillRemaining(
                child: Center(
                    child: Text('Error: $e',
                        style: const TextStyle(color: Colors.red))),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryItem(
      BuildContext context, LibraryFilter filter, dynamic item) {
    switch (filter) {
      case LibraryFilter.allSongs:
        return SongTile(
          song: item,
          onTap: () {
            ref.read(playerProvider.notifier).setQueue([item], 0);
          },
        );

      case LibraryFilter.playlists:
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.topLevel,
              borderRadius: BorderRadius.circular(6),
            ),
            child:
                const Icon(Icons.music_note_rounded, color: AppTheme.spotifyGreen),
          ),
          title: Text(item.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          subtitle: Text('Playlist • ${item.songCount} songs',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlaylistDetailsScreen(playlist: item)),
          ),
          onLongPress: () => _showPlaylistOptions(context, item),
        );

      case LibraryFilter.albums:
        final service = ref.read(subsonicServiceProvider);
        final String coverUrl = service.getCoverArtUrl(item.coverArt);
        final String coverCacheKey = 'cover_${item.coverArt ?? item.id}';

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppTheme.topLevel,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                cacheKey: coverCacheKey,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.album_rounded,
                    color: AppTheme.textMuted),
              ),
            ),
          ),
          title: Text(item.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          subtitle: Text('Album • ${item.artist}',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
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
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _showPlaylistOptions(BuildContext context, dynamic playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceLevel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.topLevel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white),
              title: const Text('Edit Playlist',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditPlaylistScreen(playlist: playlist),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Delete Playlist',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, playlist);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, dynamic playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceLevel,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Playlist',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${playlist.name}"?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white)),
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
                    SnackBar(content: Text('Deleted "${playlist.name}"')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete playlist: $e')),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SpotifyFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpotifyFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoClickable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}