// =============================================================================
// Home Screen — Spotify Encore & Music-First Experience
// -----------------------------------------------------------------------------
// Music-first layout:
//   1. Pinned Greeting Header with Settings & Filter Chips
//   2. Spotify Signature 6-Item Quick Play Grid (real album/playlist art)
//   3. "Jump Back In" Asymmetric Featured Hero
//   4. "Recently Played" Albums & Tracks Shelves (Large art cards)
//   5. "Made For You & Mixes" Visual Music Shelves
//   6. "2026 Replay" Full-Width Ambient Card
//   7. Listening Insights
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:shimmer/shimmer.dart';

import '../models/playlist.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import 'settings_screen.dart';
import 'playlist_details_screen.dart';
import 'album_details_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../features/ai_shuffle/ui/home_stats_widget.dart';
import 'made_for_you_screen.dart';
import 'new_releases_screen.dart';
import 'favorites_screen.dart';
import 'navivibe_replay_screen.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_scaffold.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _recentTab;
  int _selectedFilterIndex = 0;

  final List<String> _filters = [
    'All',
    'Smart Shuffle',
    'Made For You',
    'Favorites',
    'New Releases',
  ];

  @override
  void initState() {
    super.initState();
    _recentTab = TabController(length: 2, vsync: this);
    _recentTab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _recentTab.dispose();
    super.dispose();
  }

  String _greet() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _onFilterTap(int index) {
    setState(() => _selectedFilterIndex = index);
    switch (index) {
      case 1:
        navigateInApp(context, const AiShuffleScreen());
        break;
      case 2:
        navigateInApp(context, const MadeForYouScreen());
        break;
      case 3:
        navigateInApp(context, const FavoritesScreen());
        break;
      case 4:
        navigateInApp(context, const NewReleasesScreen());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final recentAlbumsAsync = ref.watch(recentlyPlayedAlbumsProvider);
    final recentTracksAsync = ref.watch(recentlyPlayedSongsProvider);
    final settings = ref.watch(settingsProvider);
    final tokens = ThemeTokens.of(context);
    final topPad = MediaQuery.of(context).padding.top;

    final displayName = settings.username.isNotEmpty
        ? settings.username[0].toUpperCase() + settings.username.substring(1)
        : '';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: RefreshIndicator(
          color: const Color(0xFF1DB954),
          backgroundColor: tokens.bgElevated,
          displacement: topPad + 60,
          onRefresh: () async {
            ref.invalidate(playlistsProvider);
            ref.invalidate(recentlyPlayedAlbumsProvider);
            ref.invalidate(recentlyPlayedSongsProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Header: Greeting + Settings ────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName.isNotEmpty
                              ? '${_greet()}, $displayName'
                              : _greet(),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                      if (!PlatformUtils.isDesktop)
                        IconButton(
                          icon: Icon(
                            Icons.settings_outlined,
                            color: tokens.textPrimary,
                            size: 24,
                          ),
                          tooltip: 'Settings',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Filter Chips Row ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final isSelected = _selectedFilterIndex == i;
                      return ActionChip(
                        label: Text(_filters[i]),
                        onPressed: () => _onFilterTap(i),
                        backgroundColor: isSelected
                            ? const Color(0xFF1DB954)
                            : tokens.bgElevated,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.black
                              : tokens.textPrimary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Spotify Signature 6-Item Quick Play Grid ────────────────────
              _buildQuickPlayGridSection(
                playlistsAsync: playlistsAsync,
                recentAlbumsAsync: recentAlbumsAsync,
                tokens: tokens,
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── "Jump back in" Asymmetric Hero ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _JumpBackInHero(
                    recentAlbumsAsync: recentAlbumsAsync,
                    recentTracksAsync: recentTracksAsync,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Recently Played (Tabbed Albums & Tracks) ────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Recently Played',
                  trailing: SizedBox(
                    height: 30,
                    child: TabBar(
                      controller: _recentTab,
                      isScrollable: true,
                      indicatorColor: const Color(0xFF1DB954),
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelColor: tokens.textPrimary,
                      unselectedLabelColor: tokens.textMuted,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(text: 'Albums'),
                        Tab(text: 'Songs'),
                      ],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _RecentlyPlayedShelf(
                  tabIndex: _recentTab.index,
                  albumsAsync: recentAlbumsAsync,
                  tracksAsync: recentTracksAsync,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Made For You / Smart Mixes Shelf ────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Made For You',
                  onSeeAll: () => navigateInApp(
                    context,
                    const MadeForYouScreen(),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: _MadeForYouShelf(),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── 2026 Replay Banner ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ReplayBanner(tokens: tokens),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Listening Insights ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Listening Insights'),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: HomeStatsWidget(period: 'weekly'),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPlayGridSection({
    required AsyncValue<List<Playlist>> playlistsAsync,
    required AsyncValue<List<Album>> recentAlbumsAsync,
    required AppThemeTokens tokens,
  }) {
    return playlistsAsync.when(
      data: (playlists) {
        final recentAlbums = recentAlbumsAsync.asData?.value ?? [];

        final List<_QuickItem> items = [];
        for (final pl in playlists.take(4)) {
          items.add(_QuickItem(
            id: pl.id,
            title: pl.name,
            coverArtId: pl.coverArt ?? '',
            isPlaylist: true,
            playlist: pl,
          ));
        }
        for (final al in recentAlbums.take(6 - items.length)) {
          items.add(_QuickItem(
            id: al.id,
            title: al.name,
            coverArtId: al.coverArt,
            isPlaylist: false,
            album: al,
          ));
        }

        if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

        return SliverLayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.crossAxisExtent >= 700;
            final columns = isWide ? 3 : 2;
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 56,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _QuickPlayTile(item: item);
                  },
                  childCount: items.length,
                ),
              ),
            );
          },
        );
      },
      loading: () => SliverLayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.crossAxisExtent >= 700;
          final columns = isWide ? 3 : 2;
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 56,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => Shimmer.fromColors(
                  baseColor: tokens.bgElevated,
                  highlightColor: tokens.bgSurface,
                  child: Container(
                    decoration: BoxDecoration(
                      color: tokens.bgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                childCount: 6,
              ),
            ),
          );
        },
      ),
      error: (context, error) => const SliverToBoxAdapter(child: SizedBox()),
    );
  }
}

// =============================================================================
// Quick Play Grid Model & Tile
// =============================================================================

class _QuickItem {
  final String id;
  final String title;
  final String coverArtId;
  final bool isPlaylist;
  final Playlist? playlist;
  final Album? album;

  const _QuickItem({
    required this.id,
    required this.title,
    required this.coverArtId,
    required this.isPlaylist,
    this.playlist,
    this.album,
  });
}

class _QuickPlayTile extends ConsumerStatefulWidget {
  const _QuickPlayTile({required this.item});
  final _QuickItem item;

  @override
  ConsumerState<_QuickPlayTile> createState() => _QuickPlayTileState();
}

class _QuickPlayTileState extends ConsumerState<_QuickPlayTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final svc = ref.watch(subsonicServiceProvider);
    final coverUrl = widget.item.coverArtId.isNotEmpty
        ? svc.getCoverArtUrl(widget.item.coverArtId)
        : null;

    return MouseRegion(
      onEnter: (event) => setState(() => _isHovered = true),
      onExit: (event) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.item.isPlaylist && widget.item.playlist != null) {
            navigateInApp(
              context,
              PlaylistDetailsScreen(playlist: widget.item.playlist!),
            );
          } else if (widget.item.album != null) {
            navigateInApp(
              context,
              AlbumDetailsScreen(album: widget.item.album!),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: tokens.bgElevated,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Cover Thumbnail
              SizedBox(
                width: 56,
                height: 56,
                child: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 112,
                        memCacheHeight: 112,
                        placeholder: (context, url) => Container(
                          color: tokens.bgSurface,
                          child: Icon(
                            widget.item.isPlaylist
                                ? Icons.queue_music_rounded
                                : Icons.album_rounded,
                            color: tokens.textMuted,
                            size: 24,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: tokens.bgSurface,
                          child: Icon(
                            widget.item.isPlaylist
                                ? Icons.queue_music_rounded
                                : Icons.album_rounded,
                            color: tokens.textMuted,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(
                        color: tokens.bgSurface,
                        child: Icon(
                          widget.item.isPlaylist
                              ? Icons.queue_music_rounded
                              : Icons.album_rounded,
                          color: tokens.textMuted,
                          size: 24,
                        ),
                      ),
              ),

              const SizedBox(width: 10),

              // Title
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),

              // Hover Play Button
              if (_isHovered)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB954),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Section Header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
    this.onSeeAll,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'Show all',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// "Jump Back In" Asymmetric Featured Hero
// =============================================================================

class _JumpBackInHero extends ConsumerWidget {
  const _JumpBackInHero({
    required this.recentAlbumsAsync,
    required this.recentTracksAsync,
  });

  final AsyncValue<List<Album>> recentAlbumsAsync;
  final AsyncValue<List<Song>> recentTracksAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final svc = ref.watch(subsonicServiceProvider);

    final recentTrack = recentTracksAsync.asData?.value.firstOrNull;
    final recentAlbum = recentAlbumsAsync.asData?.value.firstOrNull;

    if (recentTrack == null && recentAlbum == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF18181B), Color(0xFF27272A)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Smart AI Shuffle',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Queue tailored to your listening taste',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => navigateInApp(context, const AiShuffleScreen()),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.black,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'Shuffle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final title = recentTrack?.title ?? recentAlbum?.name ?? '';
    final subtitle = recentTrack?.artist ?? recentAlbum?.artist ?? '';
    final coverArtId = recentTrack?.coverArt ?? recentAlbum?.coverArt ?? '';
    final coverUrl = coverArtId.isNotEmpty ? svc.getCoverArtUrl(coverArtId) : null;

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background ambient artwork blur
          if (coverUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Gradient scrim
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    tokens.bgElevated.withValues(alpha: 0.95),
                    tokens.bgElevated.withValues(alpha: 0.70),
                  ],
                ),
              ),
            ),
          ),

          // Content Row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Real Artwork Tile
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 108,
                    height: 108,
                    child: coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 216,
                            memCacheHeight: 216,
                            placeholder: (context, url) => Container(
                              color: tokens.bgSurface,
                              child: const Icon(Icons.music_note_rounded),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: tokens.bgSurface,
                              child: const Icon(Icons.music_note_rounded),
                            ),
                          )
                        : Container(
                            color: tokens.bgSurface,
                            child: const Icon(Icons.music_note_rounded),
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // Title & Subtitle + Play Button
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'JUMP BACK IN',
                          style: TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Play Button
                GestureDetector(
                  onTap: () async {
                    if (recentTrack != null) {
                      await ref
                          .read(playerProvider.notifier)
                          .setQueue([recentTrack], 0);
                    } else if (recentAlbum != null) {
                      final albumSongs = await ref
                          .read(subsonicServiceProvider)
                          .getAlbum(recentAlbum.id);
                      if (albumSongs.isNotEmpty) {
                        await ref
                            .read(playerProvider.notifier)
                            .setQueue(albumSongs, 0);
                      }
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB954),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x661DB954),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Recently Played Shelf (Albums & Tracks)
// =============================================================================

class _RecentlyPlayedShelf extends ConsumerWidget {
  const _RecentlyPlayedShelf({
    required this.tabIndex,
    required this.albumsAsync,
    required this.tracksAsync,
  });

  final int tabIndex;
  final AsyncValue<List<Album>> albumsAsync;
  final AsyncValue<List<Song>> tracksAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final svc = ref.watch(subsonicServiceProvider);

    if (tabIndex == 0) {
      // Albums
      return albumsAsync.when(
        data: (albums) {
          if (albums.isEmpty) return _emptyHint('No recently played albums', tokens);
          return SizedBox(
            height: 200,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final album = albums[index];
                final coverUrl = album.coverArt.isNotEmpty
                    ? svc.getCoverArtUrl(album.coverArt)
                    : null;
                return GestureDetector(
                  onTap: () => navigateInApp(
                    context,
                    AlbumDetailsScreen(album: album),
                  ),
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 140,
                            height: 140,
                            child: coverUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 280,
                                    memCacheHeight: 280,
                                    placeholder: (context, url) => Container(
                                      color: tokens.bgSurface,
                                      child: const Icon(Icons.album_rounded),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: tokens.bgSurface,
                                      child: const Icon(Icons.album_rounded),
                                    ),
                                  )
                                : Container(
                                    color: tokens.bgSurface,
                                    child: const Icon(Icons.album_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          album.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => _shimmerShelf(tokens),
        error: (context, error) => const SizedBox(),
      );
    } else {
      // Tracks
      return tracksAsync.when(
        data: (songs) {
          if (songs.isEmpty) return _emptyHint('No recently played songs', tokens);
          return SizedBox(
            height: 200,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: songs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final song = songs[index];
                final coverUrl = song.coverArt.isNotEmpty
                    ? svc.getCoverArtUrl(song.coverArt)
                    : null;
                return GestureDetector(
                  onTap: () =>
                      ref.read(playerProvider.notifier).setQueue([song], 0),
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 140,
                            height: 140,
                            child: coverUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: coverUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 280,
                                    memCacheHeight: 280,
                                    placeholder: (context, url) => Container(
                                      color: tokens.bgSurface,
                                      child: const Icon(Icons.music_note_rounded),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: tokens.bgSurface,
                                      child: const Icon(Icons.music_note_rounded),
                                    ),
                                  )
                                : Container(
                                    color: tokens.bgSurface,
                                    child: const Icon(Icons.music_note_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => _shimmerShelf(tokens),
        error: (context, error) => const SizedBox(),
      );
    }
  }

  Widget _emptyHint(String text, AppThemeTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: TextStyle(color: tokens.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _shimmerShelf(AppThemeTokens tokens) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) => Shimmer.fromColors(
          baseColor: tokens.bgElevated,
          highlightColor: tokens.bgSurface,
          child: Container(
            width: 140,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Made For You Shelf
// =============================================================================

class _MadeForYouShelf extends ConsumerWidget {
  const _MadeForYouShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final items = [
      _MixItem(
        title: 'Smart Shuffle',
        subtitle: 'AI queue matching time & taste',
        backgroundColor: tokens.bgElevated,
        icon: Icons.auto_awesome_rounded,
        iconColor: const Color(0xFF1DB954),
        onTap: () => navigateInApp(context, const AiShuffleScreen()),
      ),
      _MixItem(
        title: 'Made For You',
        subtitle: 'Personalized playlists & mix',
        backgroundColor: tokens.bgElevated,
        icon: Icons.library_music_rounded,
        iconColor: const Color(0xFFE5E5E5),
        onTap: () => navigateInApp(context, const MadeForYouScreen()),
      ),
      _MixItem(
        title: 'Favorites Radio',
        subtitle: 'Endless mix of loved tracks',
        backgroundColor: tokens.bgElevated,
        icon: Icons.favorite_rounded,
        iconColor: const Color(0xFFD4AF37),
        onTap: () => navigateInApp(context, const FavoritesScreen()),
      ),
      _MixItem(
        title: 'New Releases',
        subtitle: 'Fresh additions to library',
        backgroundColor: tokens.bgElevated,
        icon: Icons.new_releases_rounded,
        iconColor: const Color(0xFF9CA3AF),
        onTap: () => navigateInApp(context, const NewReleasesScreen()),
      ),
    ];

    return SizedBox(
      height: 150,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return GestureDetector(
            onTap: item.onTap,
            child: Container(
              width: 140,
              decoration: BoxDecoration(
                color: item.backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, color: item.iconColor, size: 26),
                  const Spacer(),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MixItem {
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MixItem({
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });
}

// =============================================================================
// Replay Banner — Sleek Obsidian Matte Studio Card
// =============================================================================

class _ReplayBanner extends StatelessWidget {
  const _ReplayBanner({required this.tokens});
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => navigateInApp(context, const NavivibeReplayScreen()),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: Color(0xFFD4AF37),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '2026 Replay',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your year in music & listening journey',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: tokens.textMuted,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}
