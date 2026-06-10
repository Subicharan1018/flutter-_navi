import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/playlist.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import 'settings_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../features/ai_shuffle/ui/home_stats_widget.dart';
import 'made_for_you_screen.dart';
import 'new_releases_screen.dart';
import 'favorites_screen.dart';

// =============================================================================
// Home Screen
// =============================================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _sc = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0);
  late final TabController _recentlyPlayedTab;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() => _scrollOffset.value = _sc.offset);
    _recentlyPlayedTab = TabController(length: 2, vsync: this);
    _recentlyPlayedTab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sc.dispose();
    _scrollOffset.dispose();
    _recentlyPlayedTab.dispose();
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
    final playlistsAsync = ref.watch(playlistsProvider);
    final recentAlbumsAsync = ref.watch(recentlyPlayedAlbumsProvider);
    final recentTracksAsync = ref.watch(recentlyPlayedSongsProvider);
    final settings = ref.watch(settingsProvider);
    final topPad = MediaQuery.of(context).padding.top;
    final tokens = ThemeTokens.of(context);
    final disableAnim = MediaQuery.of(context).disableAnimations;

    // Parse host for subtitle
    String serverHost = '';
    try {
      final uri = Uri.tryParse(settings.serverUrl);
      serverHost = uri?.host ?? settings.serverUrl;
    } catch (_) {
      serverHost = settings.serverUrl;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: Stack(
          children: [
            // ── Main scroll ──────────────────────────────────────────────────
            RefreshIndicator(
              color: tokens.accent,
              backgroundColor: tokens.bgSurface,
              displacement: topPad + 56,
              onRefresh: () async {
                ref.invalidate(playlistsProvider);
                ref.invalidate(recentlyPlayedAlbumsProvider);
                ref.invalidate(recentlyPlayedSongsProvider);
              },
              child: CustomScrollView(
                controller: _sc,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Greeting header ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Builder(builder: (ctx) {
                      final header = _HomeHeader(
                        greeting: _greet(),
                        username: settings.username,
                        serverHost: serverHost,
                        topPad: topPad,
                        onSettings: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        ),
                      );
                      return disableAnim
                          ? header
                          : header
                              .animate()
                              .fadeIn(duration: 500.ms)
                              .slideY(
                                begin: -0.04,
                                end: 0,
                                curve: Curves.easeOutCubic,
                              );
                    }),
                  ),

                  // ── Explore ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(title: 'Explore'),
                  ),
                  SliverToBoxAdapter(
                    child: (() {
                      final child = _ExploreRow();
                      return disableAnim
                          ? child
                          : child
                              .animate(delay: 60.ms)
                              .fadeIn(duration: 400.ms);
                    }()),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 4)),

                  // ── Recently Played ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(title: 'Recently Played'),
                  ),
                  SliverToBoxAdapter(
                    child: (() {
                      final child = _RecentlyPlayedSection(
                        tabController: _recentlyPlayedTab,
                        albumsAsync: recentAlbumsAsync,
                        tracksAsync: recentTracksAsync,
                      );
                      return disableAnim
                          ? child
                          : child
                              .animate(delay: 80.ms)
                              .fadeIn(duration: 400.ms);
                    }()),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 4)),

                  // ── Quick Play ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionLabel(title: 'Quick Play'),
                  ),
                  SliverToBoxAdapter(
                    child: playlistsAsync.when(
                      data: (playlists) {
                        if (playlists.isEmpty) return const SizedBox();
                        final grid = _QuickPlayGrid(
                          items: playlists.take(6).toList(),
                          onTap: (pl) async {
                            final svc = ref.read(subsonicServiceProvider);
                            try {
                              final songs =
                                  await svc.getPlaylistSongs(pl.id);
                              if (context.mounted) {
                                ref
                                    .read(playerProvider.notifier)
                                    .setQueue(songs, 0);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not load "${pl.name}". Check your connection.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        );
                        return disableAnim
                            ? grid
                            : grid
                                .animate(delay: 100.ms)
                                .fadeIn(duration: 400.ms);
                      },
                      loading: () => const _ShimmerGrid(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),

                  // ── Monthly Replay ────────────────────────────────────────
                  const SliverToBoxAdapter(
                    child: HomeStatsWidget(period: 'monthly'),
                  ),

                  // ── Weekly Replay ─────────────────────────────────────────
                  const SliverToBoxAdapter(
                    child: HomeStatsWidget(period: 'weekly'),
                  ),

                  // Bottom safe spacing for mini player
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              ),
            ),

            // ── Frosted sticky top bar (appears on scroll) ────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
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
                          color: tokens.bgBase.withValues(alpha: 0.90),
                          padding:
                              EdgeInsets.fromLTRB(20, topPad + 10, 20, 0),
                          child: Row(
                            children: [
                              Text('Home', style: tokens.headingSm),
                              const Spacer(),
                              _TopBarIcon(
                                icon: Icons.settings_outlined,
                                label: 'Settings',
                                onTap: () => Navigator.push(
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
// Header — greeting + username + server host
// =============================================================================

class _HomeHeader extends ConsumerWidget {
  final String greeting;
  final String username;
  final String serverHost;
  final double topPad;
  final VoidCallback onSettings;

  const _HomeHeader({
    required this.greeting,
    required this.username,
    required this.serverHost,
    required this.topPad,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final displayName =
        username.isNotEmpty ? username[0].toUpperCase() + username.substring(1) : '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 24, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty ? '$greeting,' : greeting,
                  style: tokens.textStyle(13, FontWeight.w500, tokens.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName.isNotEmpty ? displayName : 'NaviVibe',
                  style: tokens.textStyle(30, FontWeight.w800, tokens.textPrimary)
                      .copyWith(
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                if (serverHost.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        serverHost,
                        style: tokens.textStyle(
                            11, FontWeight.w500, tokens.textMuted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: 'Open Settings',
            child: CupertinoClickable(
              onTap: onSettings,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: tokens.outline.withValues(alpha: 0.6), width: 0.8),
                ),
                child: Icon(
                  Icons.settings_outlined,
                  color: tokens.textSecondary,
                  size: 20,
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
// Explore Row — theme-adaptive action cards with CupertinoClickable
// =============================================================================

class _ExploreRow extends StatelessWidget {
  const _ExploreRow();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);

    final greenAccent = t.mode == AppThemeMode.spotify
        ? const Color(0xFF1DB954)
        : t.accent;
    final roseAccent = t.mode == AppThemeMode.spotify
        ? const Color(0xFFF43F5E)
        : Color.lerp(t.accent, const Color(0xFFF43F5E), 0.55)!;
    final blueAccent = t.mode == AppThemeMode.spotify
        ? const Color(0xFF3B82F6)
        : Color.lerp(t.accent, const Color(0xFF3B82F6), 0.55)!;
    final purpleAccent = t.mode == AppThemeMode.spotify
        ? const Color(0xFF9333EA)
        : Color.lerp(t.accent, const Color(0xFF9333EA), 0.55)!;

    Color cardBg(Color accent) => t.isLight
        ? Color.alphaBlend(accent.withValues(alpha: 0.10), t.bgSurface)
        : Color.alphaBlend(accent.withValues(alpha: 0.16), t.bgBase);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_made_for_you'),
                  height: 140,
                  title: 'Made\nFor You',
                  icon: Icons.auto_awesome_rounded,
                  color: greenAccent,
                  bgColor: cardBg(greenAccent),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MadeForYouScreen())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_ai_shuffle'),
                  height: 140,
                  title: 'AI\nShuffle',
                  icon: Icons.auto_awesome,
                  color: purpleAccent,
                  bgColor: cardBg(purpleAccent),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AiShuffleScreen())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_favorites'),
                  height: 100,
                  title: 'Your\nFavorites',
                  icon: Icons.favorite_rounded,
                  color: roseAccent,
                  bgColor: cardBg(roseAccent),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_new_releases'),
                  height: 100,
                  title: 'New\nReleases',
                  icon: Icons.new_releases_rounded,
                  color: blueAccent,
                  bgColor: cardBg(blueAccent),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NewReleasesScreen())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  final double height;
  final String title;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _ExploreCard({
    super.key,
    required this.height,
    required this.title,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: title.replaceAll('\n', ' '),
      child: CupertinoClickable(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.20),
              width: 0.8,
            ),
          ),
          child: Stack(
            children: [
              // Background icon watermark
              Positioned(
                right: -10,
                top: -10,
                child: Icon(
                  icon,
                  color: color.withValues(alpha: 0.09),
                  size: 96,
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .textStyle(15, FontWeight.w700, tokens.textPrimary)
                          .copyWith(height: 1.2),
                    ),
                  ],
                ),
              ),
              // Arrow badge
              Positioned(
                bottom: 14,
                right: 14,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: color,
                    size: 14,
                  ),
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
// Recently Played Section — segmented tab + carousel
// =============================================================================

class _RecentlyPlayedSection extends ConsumerStatefulWidget {
  final TabController tabController;
  final AsyncValue<List<Album>> albumsAsync;
  final AsyncValue<List<Song>> tracksAsync;

  const _RecentlyPlayedSection({
    required this.tabController,
    required this.albumsAsync,
    required this.tracksAsync,
  });

  @override
  ConsumerState<_RecentlyPlayedSection> createState() =>
      _RecentlyPlayedSectionState();
}

class _RecentlyPlayedSectionState
    extends ConsumerState<_RecentlyPlayedSection> {
  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Segment selector ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ThemeSegmentedControl(
            controller: widget.tabController,
            labels: const ['Albums', 'Tracks'],
          ),
        ),
        const SizedBox(height: 14),

        // ── Content carousel ───────────────────────────────────────────────
        SizedBox(
          height: 196,
          child: widget.tabController.index == 0
              ? _AlbumCarousel(albumsAsync: widget.albumsAsync)
              : _TrackCarousel(tracksAsync: widget.tracksAsync),
        ),
      ],
    );
  }
}

// =============================================================================
// Theme-aware segmented control
// =============================================================================

class _ThemeSegmentedControl extends StatelessWidget {
  final TabController controller;
  final List<String> labels;

  const _ThemeSegmentedControl({
    required this.controller,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);

    switch (t.mode) {
      case AppThemeMode.neumorphic:
        return _NeuSegmentedControl(controller: controller, labels: labels);
      case AppThemeMode.frost:
        return _FrostSegmentedControl(controller: controller, labels: labels);
      case AppThemeMode.zen:
        return _ZenSegmentedControl(controller: controller, labels: labels);
      default:
        return _DefaultSegmentedControl(controller: controller, labels: labels);
    }
  }
}

class _DefaultSegmentedControl extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const _DefaultSegmentedControl(
      {required this.controller, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final selectedIdx = controller.index;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.outline, width: 0.7),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == selectedIdx;
          return Expanded(
            child: CupertinoClickable(
              onTap: () => controller.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isActive ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: t.textStyle(
                    13,
                    isActive ? FontWeight.w700 : FontWeight.w500,
                    isActive
                        ? (t.isLight ? Colors.white : Colors.black)
                        : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NeuSegmentedControl extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const _NeuSegmentedControl(
      {required this.controller, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final selectedIdx = controller.index;
    return NeuBox(
      padding: const EdgeInsets.all(3),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == selectedIdx;
          return Expanded(
            child: CupertinoClickable(
              onTap: () => controller.animateTo(i),
              child: NeuBox(
                isPressed: isActive,
                borderRadius: BorderRadius.circular(9),
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Center(
                  child: Text(
                    labels[i],
                    style: t.textStyle(
                      13,
                      isActive ? FontWeight.w700 : FontWeight.w500,
                      isActive ? t.accent : t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FrostSegmentedControl extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const _FrostSegmentedControl(
      {required this.controller, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final selectedIdx = controller.index;
    return GlassBox(
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == selectedIdx;
          return Expanded(
            child: CupertinoClickable(
              onTap: () => controller.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.all(2),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isActive
                      ? t.accent.withValues(alpha: 0.35)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: isActive
                      ? Border.all(
                          color: t.accent.withValues(alpha: 0.5), width: 0.8)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: t.textStyle(
                    13,
                    isActive ? FontWeight.w700 : FontWeight.w500,
                    isActive ? t.textPrimary : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ZenSegmentedControl extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const _ZenSegmentedControl(
      {required this.controller, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final selectedIdx = controller.index;
    return Row(
      children: [
        ...List.generate(labels.length, (i) {
          final isActive = i == selectedIdx;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: CupertinoClickable(
              onTap: () => controller.animateTo(i),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[i],
                    style: t.textStyle(
                      15,
                      isActive ? FontWeight.w700 : FontWeight.w400,
                      isActive ? t.textPrimary : t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 2,
                    width: isActive ? 24.0 : 0,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// =============================================================================
// Album carousel
// =============================================================================

class _AlbumCarousel extends ConsumerWidget {
  final AsyncValue<List<Album>> albumsAsync;
  const _AlbumCarousel({required this.albumsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return albumsAsync.when(
      loading: () => const _ShimmerReel(),
      error: (_, __) => const _EmptyCarouselHint(
        icon: Icons.album_rounded,
        text: 'No recent albums — start playing something!',
      ),
      data: (albums) {
        if (albums.isEmpty) {
          return const _EmptyCarouselHint(
            icon: Icons.album_rounded,
            text: 'No recent albums yet — start playing something!',
          );
        }
        final svc = ref.watch(subsonicServiceProvider);
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: albums.length,
          itemBuilder: (ctx, i) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AlbumCard(
              album: albums[i],
              rank: i,
              coverUrl: albums[i].coverArt.isNotEmpty
                  ? svc.getCoverArtUrl(albums[i].coverArt)
                  : null,
              onTap: () async {
                try {
                  final songs = await svc.getAlbum(albums[i].id);
                  if (ctx.mounted) {
                    ref.read(playerProvider.notifier).setQueue(songs, 0);
                  }
                } catch (_) {}
              },
            ),
          ),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final int rank;
  final String? coverUrl;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.album,
    required this.rank,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Play album: ${album.name} by ${album.artist}',
      child: CupertinoClickable(
        onTap: onTap,
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (coverUrl != null)
                        CachedNetworkImage(
                          imageUrl: coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _artPlaceholder(t),
                          errorWidget: (_, __, ___) => _artPlaceholder(t),
                        )
                      else
                        _artPlaceholder(t),
                      // Play overlay
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.accent.withValues(alpha: 0.92),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: t.isLight ? Colors.white : Colors.black,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textStyle(12, FontWeight.w700, t.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textStyle(11, FontWeight.w400, t.textSecondary),
              ),
            ],
          ),
        )
            .animate(delay: (rank * 40).clamp(0, 200).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _artPlaceholder(AppThemeTokens t) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accent.withValues(alpha: 0.5),
              t.accentDim.withValues(alpha: 0.25),
            ],
          ),
        ),
        child: Icon(Icons.album_rounded, color: Colors.white30, size: 40),
      );
}

// =============================================================================
// Track carousel
// =============================================================================

class _TrackCarousel extends ConsumerWidget {
  final AsyncValue<List<Song>> tracksAsync;
  const _TrackCarousel({required this.tracksAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return tracksAsync.when(
      loading: () => const _ShimmerReel(),
      error: (_, __) => const _EmptyCarouselHint(
        icon: Icons.music_note_rounded,
        text: 'No history yet — start listening!',
      ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const _EmptyCarouselHint(
            icon: Icons.music_note_rounded,
            text: 'Play some songs to build your history.',
          );
        }
        final svc = ref.watch(subsonicServiceProvider);
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: tracks.length,
          itemBuilder: (ctx, i) {
            final song = tracks[i];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _TrackCard(
                song: song,
                rank: i,
                coverUrl: svc.getCoverArtUrl(song.coverArt),
                onTap: () {
                  ref.read(playerProvider.notifier).setQueue(tracks, i);
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Song song;
  final int rank;
  final String coverUrl;
  final VoidCallback onTap;

  const _TrackCard({
    required this.song,
    required this.rank,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Play: ${song.title} by ${song.artist}',
      child: CupertinoClickable(
        onTap: onTap,
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _artPlaceholder(t),
                        errorWidget: (_, __, ___) => _artPlaceholder(t),
                      ),
                      // Play overlay
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.accent.withValues(alpha: 0.9),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: t.isLight ? Colors.white : Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textStyle(12, FontWeight.w700, t.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textStyle(11, FontWeight.w400, t.textSecondary),
              ),
            ],
          ),
        )
            .animate(delay: (rank * 40).clamp(0, 200).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _artPlaceholder(AppThemeTokens t) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accent.withValues(alpha: 0.5),
              t.accentDim.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: Icon(Icons.music_note_rounded, color: Colors.white30, size: 36),
      );
}

// =============================================================================
// Empty carousel hint
// =============================================================================

class _EmptyCarouselHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyCarouselHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 196,
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.outline, width: 0.7),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: t.textMuted, size: 32),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: t.textStyle(13, FontWeight.w400, t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Play Grid — 2-column tiled playlist rows
// =============================================================================

class _QuickPlayGrid extends StatelessWidget {
  final List<Playlist> items;
  final void Function(Playlist) onTap;
  const _QuickPlayGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();

    final t = ThemeTokens.of(context);
    final palette = [
      t.accent,
      t.gold,
      Color.lerp(t.accent, t.gold, 0.5) ?? t.accent,
      Color.lerp(t.accent, t.bgElevated, 0.35) ?? t.accent,
      Color.lerp(t.gold, t.accentDim, 0.4) ?? t.gold,
      t.accentDim,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int r = 0; r < (items.length / 2).ceil(); r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (int c = 0; c < 2; c++)
                    Builder(
                      builder: (_) {
                        final i = r * 2 + c;
                        if (i >= items.length) {
                          return const Expanded(child: SizedBox());
                        }
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: c == 1 ? 8 : 0),
                            child: _QuickTile(
                              playlist: items[i],
                              accentColor: palette[i % 6],
                              index: i,
                              onTap: () => onTap(items[i]),
                            ),
                          ),
                        );
                      },
                    ),
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
  final Color accentColor;
  final int index;
  final VoidCallback onTap;
  const _QuickTile({
    required this.playlist,
    required this.accentColor,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final tokens = ThemeTokens.of(context);

    final tile = Semantics(
      button: true,
      label: 'Play playlist: ${playlist.name}',
      child: CupertinoClickable(
        onTap: onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.14),
              width: 0.7,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              // Artwork
              SizedBox(
                width: 58,
                height: 58,
                child: playlist.coverArt != null
                    ? CachedNetworkImage(
                        imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withValues(alpha: 0.8),
                              accentColor.withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.queue_music_rounded,
                          color:
                              tokens.textPrimary.withValues(alpha: 0.7),
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                      13, FontWeight.w600, tokens.textPrimary),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    color: accentColor, size: 16),
              ),
            ],
          ),
        ),
      ),
    );

    final disableAnim = MediaQuery.of(context).disableAnimations;
    return disableAnim
        ? tile
        : tile
            .animate(delay: (index * 40).clamp(0, 200).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
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
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: tokens.headingSm)),
          if (onSeeAll != null)
            Semantics(
              button: true,
              label: 'See all $title',
              child: GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.accent,
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
// Top bar icon button
// =============================================================================

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TopBarIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          icon: Icon(icon, color: tokens.textSecondary, size: 22),
          onPressed: onTap,
        ),
      ),
    );
  }
}

// =============================================================================
// Shimmer placeholders
// =============================================================================

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(
          3,
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: List.generate(
                2,
                (c) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: c == 1 ? 8 : 0),
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: tokens.bgSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
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

class _ShimmerReel extends StatelessWidget {
  const _ShimmerReel();

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 700.ms)
        .then()
        .fadeOut(duration: 700.ms);
  }
}
