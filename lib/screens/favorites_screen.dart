import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/song_tile.dart';
import '../core/theme.dart';

// =============================================================================
// FavoritesScreen — Spotify dark theme
// NO own MiniPlayer — AppScaffold provides it for all tabs.
// =============================================================================

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _selectedTab = 0; // 0: Songs, 1: Albums

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeTokens.of(context).isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: RefreshIndicator(
          color: ThemeTokens.of(context).accent,
          backgroundColor: ThemeTokens.of(context).bgSurface,
          displacement: topPad + 56,
          onRefresh: () async {
            ref.invalidate(favoritesProvider);
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _FavoritesHeader(
                  topPad: topPad,
                  selectedTab: _selectedTab,
                  onTabChanged: (t) => setState(() => _selectedTab = t),
                  favoritesAsync: favoritesAsync,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // ── Content ─────────────────────────────────────────────────
              favoritesAsync.when(
                data: (data) {
                  if (_selectedTab == 0) {
                    return _buildSongsList(data.songs);
                  } else {
                    return _buildAlbumsGrid(data.albums);
                  }
                },
                loading: () => SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: ThemeTokens.of(context).accent,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Could not load favorites',
                      style: TextStyle(
                        color: ThemeTokens.of(context).textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom spacing for mini player
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongsList(List<Song> songs) {
    if (songs.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(
          icon: Icons.favorite_border_rounded,
          message: 'No favorite songs yet',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final song = songs[index];
        return SongTile(
              song: song,
              onTap: () {
                ref.read(playerProvider.notifier).setQueue(songs, index);
              },
            )
            .animate(delay: (index * 18).clamp(0, 280).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.03, end: 0, curve: Curves.easeOutCubic);
      }, childCount: songs.length),
    );
  }

  Widget _buildAlbumsGrid(List<Album> albums) {
    if (albums.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(
          icon: Icons.album_outlined,
          message: 'No favorite albums yet',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final album = albums[index];
          return _AlbumCard(
                album: album,
                onTap: () async {
                  try {
                    final svc = ref.read(subsonicServiceProvider);
                    final songs = await svc.getAlbum(album.id);
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
              )
              .animate(delay: (index * 40).clamp(0, 320).ms)
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
        }, childCount: albums.length),
      ),
    );
  }
}

// =============================================================================
// Header — Spotify-styled with green accent, count badge, filter pills
// =============================================================================

class _FavoritesHeader extends StatelessWidget {
  final double topPad;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final AsyncValue<({List<Song> songs, List<Album> albums})> favoritesAsync;

  const _FavoritesHeader({
    required this.topPad,
    required this.selectedTab,
    required this.onTabChanged,
    required this.favoritesAsync,
  });

  @override
  Widget build(BuildContext context) {
    final songCount = favoritesAsync.asData?.value.songs.length ?? 0;
    final albumCount = favoritesAsync.asData?.value.albums.length ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtitle label
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: ThemeTokens.of(context).accent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'COLLECTION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: ThemeTokens.of(context).accent,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Title
          Text('Favorites', style: ThemeTokens.of(context).headingLg),
          SizedBox(height: 6),
          // Count
          Text(
            '$songCount songs • $albumCount albums',
            style: TextStyle(
              fontSize: 13,
              color: ThemeTokens.of(context).textSecondary,
            ),
          ),
          SizedBox(height: 20),
          // Filter pills
          Row(
            children: [
              _FilterPill(
                title: 'Songs',
                isSelected: selectedTab == 0,
                onTap: () => onTabChanged(0),
              ),
              SizedBox(width: 8),
              _FilterPill(
                title: 'Albums',
                isSelected: selectedTab == 1,
                onTap: () => onTabChanged(1),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.03, end: 0);
  }
}

// =============================================================================
// Filter pill — Spotify green when selected
// =============================================================================

class _FilterPill extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterPill({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title filter${isSelected ? ", selected" : ""}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? ThemeTokens.of(context).accent
                : ThemeTokens.of(context).bgElevated,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? (ThemeTokens.of(context).isLight
                        ? Colors.white
                        : Colors.black)
                  : ThemeTokens.of(context).textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Album card — Spotify grid style with cached artwork
// =============================================================================

class _AlbumCard extends ConsumerWidget {
  final Album album;
  final VoidCallback onTap;
  const _AlbumCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final coverUrl = album.coverArt.isNotEmpty
        ? svc.getCoverArtUrl(album.coverArt)
        : null;

    return Semantics(
      button: true,
      label: 'Play album: ${album.name} by ${album.artist}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: ThemeTokens.of(context).bgElevated,
                ),
                clipBehavior: Clip.hardEdge,
                child: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheKey:
                            'fav_album_${album.coverArt.isNotEmpty ? album.coverArt : album.id}',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: 350,
                        memCacheHeight: 350,
                        placeholder: (context, url) => Container(
                          color: ThemeTokens.of(context).bgElevated,
                          child: Center(
                            child: Icon(
                              Icons.album_rounded,
                              color: ThemeTokens.of(context).textMuted,
                              size: 40,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: ThemeTokens.of(context).bgElevated,
                          child: Center(
                            child: Icon(
                              Icons.album_rounded,
                              color: ThemeTokens.of(context).textMuted,
                              size: 40,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.album_rounded,
                          color: ThemeTokens.of(context).textMuted,
                          size: 40,
                        ),
                      ),
              ),
            ),
            SizedBox(height: 8),
            // Title
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeTokens.of(context).textPrimary,
              ),
            ),
            SizedBox(height: 2),
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: ThemeTokens.of(context).textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: ThemeTokens.of(context).textMuted, size: 48),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: ThemeTokens.of(context).textMuted,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
