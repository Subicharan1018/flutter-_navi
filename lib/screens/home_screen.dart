import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/replay_provider.dart';
import '../core/theme.dart';
import 'settings_screen.dart';
import 'made_for_you_screen.dart';
import 'new_releases_screen.dart';
import 'favorites_screen.dart';
import 'replay_screen.dart';

// =============================================================================
// Home Screen
// Spotify dark theme. One playlist section only (Quick Play grid).
// Monthly Replay and Weekly Replay backed by real SQLite analytics.
// =============================================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _sc = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sc.addListener(() => _scrollOffset.value = _sc.offset);
  }

  @override
  void dispose() {
    _sc.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  String _greet() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync    = ref.watch(playlistsProvider);
    final monthlyAsync      = ref.watch(monthlyReplayProvider);
    final weeklyAsync       = ref.watch(weeklyReplayProvider);
    final topPad            = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.coreBackground,
        body: Stack(
          children: [
            // ── Main scroll ───────────────────────────────────────────────────
            RefreshIndicator(
              color: AppTheme.spotifyGreen,
              backgroundColor: AppTheme.surfaceLevel,
              displacement: topPad + 56,
              onRefresh: () async {
                ref.invalidate(playlistsProvider);
                ref.invalidate(monthlyReplayProvider);
                ref.invalidate(weeklyReplayProvider);
              },
              child: CustomScrollView(
                controller: _sc,
                physics: const BouncingScrollPhysics(),
                slivers: [

                  // ── Greeting header ─────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _HomeHeader(
                      greeting: _greet(),
                      topPad: topPad,
                      onSettings: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: -0.04, end: 0, curve: Curves.easeOutCubic),
                  ),

                  // ── Explore cards ────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(title: 'Explore'),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ExploreCard(
                              key: const Key('explore_made_for_you'),
                              label: 'CURATED',
                              title: 'Made\nFor You',
                              icon: Icons.auto_awesome_rounded,
                              color: const Color(0xFF1DB954),
                              bgColor: const Color(0xFF0A1F12),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const MadeForYouScreen())),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ExploreCard(
                              key: const Key('explore_favorites'),
                              label: 'SAVED',
                              title: 'Your\nFavorites',
                              icon: Icons.favorite_rounded,
                              color: const Color(0xFFF43F5E),
                              bgColor: const Color(0xFF1F0A0E),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ExploreCard(
                              key: const Key('explore_new_releases'),
                              label: 'FRESH',
                              title: 'New\nReleases',
                              icon: Icons.new_releases_rounded,
                              color: const Color(0xFF3B82F6),
                              bgColor: const Color(0xFF08101A),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const NewReleasesScreen())),
                            ),
                          ),
                        ],
                      ),
                    ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 4)),

                  // ── Quick Play — playlists, ONE section only ──────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(title: 'Quick Play'),
                  ),
                  SliverToBoxAdapter(
                    child: playlistsAsync.when(
                      data: (playlists) {
                        if (playlists.isEmpty) return const SizedBox();
                        return _QuickPlayGrid(
                          items: playlists.take(6).toList(),
                          onTap: (pl) async {
                            final svc = ref.read(subsonicServiceProvider);
                            try {
                              final songs = await svc.getPlaylistSongs(pl.id);
                              if (context.mounted) {
                                ref.read(playerProvider.notifier).setQueue(songs, 0);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not play "${pl.name}": $e')),
                                );
                              }
                            }
                          },
                        ).animate(delay: 100.ms).fadeIn(duration: 400.ms);
                      },
                      loading: () => const _ShimmerGrid(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),

                  // ── Monthly Replay ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(
                      title: 'Monthly Replay',
                      onSeeAll: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ReplayScreen(initialTab: 0))),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: monthlyAsync.when(
                      data: (data) => data.isEmpty
                          ? const _EmptyReplayHint()
                          : _ReplaySongReel(
                              data: data,
                              onSeeAll: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const ReplayScreen(initialTab: 0))),
                            ).animate(delay: 140.ms).fadeIn(duration: 400.ms),
                      loading: () => const _ShimmerReel(),
                      error: (_, __) => const _EmptyReplayHint(),
                    ),
                  ),

                  // ── Weekly Replay ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(
                      title: 'This Week',
                      onSeeAll: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ReplayScreen(initialTab: 1))),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: weeklyAsync.when(
                      data: (data) => data.isEmpty
                          ? const _EmptyReplayHint()
                          : _ReplaySongReel(
                              data: data,
                              onSeeAll: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const ReplayScreen(initialTab: 1))),
                            ).animate(delay: 180.ms).fadeIn(duration: 400.ms),
                      loading: () => const _ShimmerReel(),
                      error: (_, __) => const _EmptyReplayHint(),
                    ),
                  ),

                  // Bottom safe spacing for mini player
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              ),
            ),

            // ── Frosted sticky top bar (appears on scroll) ────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) {
                  final t = (offset / 60).clamp(0.0, 1.0);
                  return AnimatedOpacity(
                    opacity: t,
                    duration: Duration.zero,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          height: topPad + 50,
                          color: AppTheme.coreBackground.withOpacity(0.90),
                          padding: EdgeInsets.fromLTRB(20, topPad + 10, 20, 0),
                          child: Row(
                            children: [
                              Text('Home', style: AppTheme.headingSm),
                              const Spacer(),
                              _TopBarIcon(
                                icon: Icons.settings_outlined,
                                label: 'Settings',
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Header
// =============================================================================

class _HomeHeader extends StatelessWidget {
  final String greeting;
  final double topPad;
  final VoidCallback onSettings;
  const _HomeHeader({required this.greeting, required this.topPad, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 20, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting.toUpperCase(),
                  style: AppTheme.labelMd,
                ),
                const SizedBox(height: 6),
                Text('Home', style: AppTheme.headingLg),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Open Settings',
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: AppTheme.textSecondary, size: 22),
                onPressed: onSettings,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Explore card — Material-3-aligned rounded card with icon + label
// =============================================================================

class _ExploreCard extends StatelessWidget {
  final String label;
  final String title;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _ExploreCard({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title.replaceAll('\n', ' '),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.18), width: 0.8),
          ),
          child: Stack(
            children: [
              // Background icon watermark
              Positioned(
                right: -8, top: -8,
                child: Icon(icon, color: color.withOpacity(0.08), size: 90),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: color,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 4),
                    Text(title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.15,
                        )),
                  ],
                ),
              ),
              // Arrow chip — bottom right
              Positioned(
                bottom: 12, right: 12,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.15),
                  ),
                  child: Icon(Icons.chevron_right_rounded, color: color, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Play Grid — 2×3 asymmetric tiles (no duplicates of playlist section)
// =============================================================================

class _QuickPlayGrid extends StatelessWidget {
  final List<Playlist> items;
  final void Function(Playlist) onTap;
  const _QuickPlayGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();

    // Build 2-column grid rows of equal-height tiles
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int r = 0; r < (items.length / 2).ceil(); r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (int c = 0; c < 2; c++) Builder(builder: (_) {
                    final i = r * 2 + c;
                    if (i >= items.length) return const Expanded(child: SizedBox());
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: c == 1 ? 8 : 0),
                        child: _QuickTile(
                          playlist: items[i],
                          index: i,
                          onTap: () => onTap(items[i]),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickTile extends ConsumerWidget {
  final Playlist playlist;
  final int index;
  final VoidCallback onTap;
  const _QuickTile({required this.playlist, required this.index, required this.onTap});

  static const _colors = [
    Color(0xFF1DB954), Color(0xFF3B82F6), Color(0xFFF43F5E),
    Color(0xFF10B981), Color(0xFFA855F7), Color(0xFF22D3EE),
  ];
  Color get _ac => _colors[index % _colors.length];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);

    return Semantics(
      button: true,
      label: 'Play playlist: ${playlist.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _ac.withOpacity(0.12), width: 0.7),
          ),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              // Artwork
              SizedBox(
                width: 56, height: 56,
                child: playlist.coverArt != null
                    ? CachedNetworkImage(
                        imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_ac.withOpacity(0.8), _ac.withOpacity(0.3)],
                          ),
                        ),
                        child: Icon(Icons.queue_music_rounded,
                            color: Colors.white.withOpacity(0.7), size: 22),
                      ),
              ),
              const SizedBox(width: 10),
              // Title — Expanded prevents overflow
              Expanded(
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              // Play icon
              Container(
                width: 28, height: 28,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ac.withOpacity(0.15),
                ),
                child: Icon(Icons.play_arrow_rounded, color: _ac, size: 16),
              ),
            ],
          ),
        ),
      ),
    )
    .animate(delay: (index * 40).clamp(0, 200).ms)
    .fadeIn(duration: 350.ms)
    .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

// =============================================================================
// Replay Song Reel — horizontal cards for Monthly / Weekly Replay
// =============================================================================

class _ReplaySongReel extends ConsumerWidget {
  final ReplayData data;
  final VoidCallback onSeeAll;
  const _ReplaySongReel({required this.data, required this.onSeeAll});

  Future<void> _playSong(BuildContext context, WidgetRef ref, ReplaySong song) async {
    try {
      final svc = ref.read(subsonicServiceProvider);
      final searchResult = await svc.search(song.title);
      final results = searchResult['songs'] as List<Song>? ?? [];
      final match = results.where((s) => s.id == song.songId).firstOrNull;
      if (match != null && context.mounted) {
        ref.read(playerProvider.notifier).setQueue([match], 0);
      } else if (results.isNotEmpty && context.mounted) {
        ref.read(playerProvider.notifier).setQueue([results.first], 0);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play "${song.title}": $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: data.songs.length,
        itemBuilder: (context, i) {
          final song = data.songs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ReplayCard(
              song: song,
              rank: i + 1,
              onTap: () => _playSong(context, ref, song),
            ),
          );
        },
      ),
    );
  }
}

class _ReplayCard extends ConsumerWidget {
  final ReplaySong song;
  final int rank;
  final VoidCallback onTap;
  const _ReplayCard({required this.song, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final coverUrl = song.coverArtId != null
        ? svc.getCoverArtUrl(song.coverArtId!)
        : null;

    return Semantics(
      button: true,
      label: 'Play rank $rank: ${song.title} by ${song.artist}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 130,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.outlineColor, width: 0.7),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album art — real cover from Subsonic
              SizedBox(
                height: 100,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverUrl != null)
                      CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheKey: 'replay_${song.songId}',
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _artGradient(),
                        errorWidget: (_, __, ___) => _artGradient(),
                      )
                    else
                      _artGradient(),
                    // Rank badge
                    Positioned(
                      top: 6, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Play overlay
                    Positioned(
                      bottom: 6, right: 6,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.spotifyGreen.withOpacity(0.9),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.black, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              // Song info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          )),
                      const SizedBox(height: 2),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          )),
                      const Spacer(),
                      // Listening time badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.spotifyGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          song.listeningLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.spotifyGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
    .animate(delay: (rank * 40).clamp(0, 240).ms)
    .fadeIn(duration: 350.ms)
    .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _artGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.spotifyGreen.withOpacity(0.6),
            AppTheme.spotifyGreen.withOpacity(0.15),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded,
            color: Colors.white38, size: 28),
      ),
    );
  }
}


// =============================================================================
// Empty state for replay sections
// =============================================================================

class _EmptyReplayHint extends StatelessWidget {
  const _EmptyReplayHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outlineColor, width: 0.7),
        ),
        child: Row(
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: AppTheme.spotifyGreen, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Start listening to build your Replay',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section label with optional "See All"
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionLabel({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: AppTheme.headingSm)),
          if (onSeeAll != null)
            Semantics(
              button: true,
              label: 'See all $title',
              child: GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.spotifyGreen,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Top bar icon button — 48dp tap target
// =============================================================================

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TopBarIcon({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          icon: Icon(icon, color: AppTheme.textSecondary, size: 22),
          onPressed: onTap,
        ),
      ),
    );
  }
}

// =============================================================================
// Shimmer placeholders (no third-party shimmer — pure animated opacity)
// =============================================================================

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(3, (r) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(2, (c) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: c == 1 ? 8 : 0),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )),
          ),
        )),
      )
      .animate(onPlay: (c) => c.repeat(reverse: true))
      .fadeIn(duration: 700.ms)
      .then()
      .fadeOut(duration: 700.ms),
    );
  }
}

class _ShimmerReel extends StatelessWidget {
  const _ShimmerReel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            width: 120,
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      )
      .animate(onPlay: (c) => c.repeat(reverse: true))
      .fadeIn(duration: 700.ms)
      .then()
      .fadeOut(duration: 700.ms),
    );
  }
}