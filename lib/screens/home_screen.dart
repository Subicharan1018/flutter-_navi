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
import '../widgets/navi_ui.dart';
import 'settings_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../features/ai_shuffle/ui/home_stats_widget.dart';
import 'made_for_you_screen.dart';
import 'new_releases_screen.dart';
import 'favorites_screen.dart';
import 'navivibe_replay_screen.dart';

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
  late final TabController _recentTab;

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

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final recentAlbumsAsync = ref.watch(recentlyPlayedAlbumsProvider);
    final recentTracksAsync = ref.watch(recentlyPlayedSongsProvider);
    final settings = ref.watch(settingsProvider);
    final tokens = ThemeTokens.of(context);
    final topPad = MediaQuery.of(context).padding.top;

    String serverHost = '';
    try {
      serverHost = Uri.tryParse(settings.serverUrl)?.host ?? '';
    } catch (_) {}

    final displayName = settings.username.isNotEmpty
        ? settings.username[0].toUpperCase() + settings.username.substring(1)
        : 'NaviVibe';

    final bottomClearance =
        68.0 + 56.0 + s16 + MediaQuery.viewPaddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: RefreshIndicator(
          color: tokens.accent,
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
              // ── Pinned SliverAppBar ─────────────────────────────────────
              SliverAppBar(
                expandedHeight: 130,
                pinned: true,
                backgroundColor: tokens.bgBase,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _SettingsButton(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: EdgeInsets.zero,
                  expandedTitleScale: 1.0,
                  title: LayoutBuilder(
                    builder: (_, constraints) {
                      final isCollapsed = constraints.maxHeight < 76;
                      return AnimatedPadding(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.fromLTRB(
                          s16,
                          0,
                          isCollapsed ? 52 : s16,
                          isCollapsed ? 14 : s16,
                        ),
                        child: isCollapsed
                            ? _CollapsedHeader(
                                tokens: tokens,
                                serverHost: serverHost,
                              )
                            : _ExpandedHeader(
                                greeting: _greet(),
                                displayName: displayName,
                                serverHost: serverHost,
                                tokens: tokens,
                              ),
                      );
                    },
                  ),
                ),
              ),

              // ── Explore ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Explore'),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: s16),
                sliver: SliverToBoxAdapter(
                  child: _ExploreGrid(context: context),
                ),
              ),

              // ── Recently Played ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Recently Played'),
              ),
              SliverToBoxAdapter(
                child: _RecentlyPlayedSection(
                  tabController: _recentTab,
                  albumsAsync: recentAlbumsAsync,
                  tracksAsync: recentTracksAsync,
                ),
              ),

              // ── Quick Play ───────────────────────────────────────────────
              playlistsAsync.when(
                data: (playlists) {
                  if (playlists.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
                  return SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionHeader(title: 'Quick Play'),
                      _QuickPlayGrid(
                        items: playlists.take(6).toList(),
                        onTap: (pl) async {
                          final svc = ref.read(subsonicServiceProvider);
                          try {
                            final songs = await svc.getPlaylistSongs(pl.id);
                            if (context.mounted) {
                              ref.read(playerProvider.notifier).setQueue(songs, 0);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not load "${pl.name}". Check your connection.'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ]),
                  );
                },
                loading: () => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(s16, 0, s16, s8),
                    child: Column(
                      children: List.generate(
                        3,
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: s8),
                          child: Row(
                            children: [
                              Expanded(child: NaviSkeleton(height: 58, borderRadius: radiusMd)),
                              const SizedBox(width: s8),
                              Expanded(child: NaviSkeleton(height: 58, borderRadius: radiusMd)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                error: (_, e) => const SliverToBoxAdapter(child: SizedBox()),
              ),

              // ── Listening highlights ─────────────────────────────────────
              SliverToBoxAdapter(child: _SectionHeader(title: 'Listening Insights')),
              const SliverToBoxAdapter(
                child: HomeStatsWidget(period: 'monthly'),
              ),
              const SliverToBoxAdapter(
                child: HomeStatsWidget(period: 'weekly'),
              ),

              SliverToBoxAdapter(child: SizedBox(height: bottomClearance)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Header — collapsed (pinned) and expanded states
// =============================================================================

class _CollapsedHeader extends StatelessWidget {
  final AppThemeTokens tokens;
  final String serverHost;
  const _CollapsedHeader({required this.tokens, required this.serverHost});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Home',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: tokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        if (serverHost.isNotEmpty) ...[
          const SizedBox(width: s8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.accent.withValues(alpha: 0.4), width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              serverHost,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: tokens.accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final String greeting;
  final String displayName;
  final String serverHost;
  final AppThemeTokens tokens;

  const _ExpandedHeader({
    required this.greeting,
    required this.displayName,
    required this.serverHost,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final mode = tokens.mode;

    final titleStyle = mode == AppThemeMode.zen
        ? tokens.textStyle(28, FontWeight.w400, tokens.textPrimary)
            .copyWith(letterSpacing: -0.5, height: 1.1)
        : mode == AppThemeMode.analog
            ? tokens.textStyle(28, FontWeight.w800, tokens.textPrimary)
                .copyWith(letterSpacing: -0.5, height: 1.1)
            : TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: tokens.textPrimary,
                letterSpacing: -0.8,
                height: 1.1,
              );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: tokens.textMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(displayName, style: titleStyle),
        if (serverHost.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: tokens.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                serverHost,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: tokens.textMuted,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SettingsButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SettingsButton({required this.onTap});

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.08), width: 0.8),
          ),
          child: Icon(
            Icons.settings_outlined,
            color: tokens.textSecondary,
            size: 18,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Section header — matches dashboard_screen._Label style
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(s16, s24, s16, s12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: s12),
          Expanded(
            child: Container(
              height: 0.5,
              color: tokens.textPrimary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Explore Grid — 2×2 equal cards + full-width Replay banner
// =============================================================================

class _ExploreGrid extends StatelessWidget {
  final BuildContext context;
  const _ExploreGrid({required this.context});

  @override
  Widget build(BuildContext outerCtx) {
    final t = ThemeTokens.of(outerCtx);

    // Four accent colours — harmonise per theme rather than hard-coding Spotify green
    final c1 = t.mode == AppThemeMode.spotify
        ? const Color(0xFF1DB954)
        : t.accent;
    final c2 = t.mode == AppThemeMode.spotify
        ? const Color(0xFF9333EA)
        : Color.lerp(t.accent, const Color(0xFF9333EA), 0.55)!;
    final c3 = t.mode == AppThemeMode.spotify
        ? const Color(0xFFF43F5E)
        : Color.lerp(t.accent, const Color(0xFFF43F5E), 0.55)!;
    final c4 = t.mode == AppThemeMode.spotify
        ? const Color(0xFF3B82F6)
        : Color.lerp(t.accent, const Color(0xFF3B82F6), 0.55)!;
    final cReplay = t.mode == AppThemeMode.spotify
        ? const Color(0xFFF59E0B)
        : Color.lerp(t.accent, const Color(0xFFF59E0B), 0.50)!;

    return Column(
      children: [
        // Row 1 — tall duo
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_made_for_you'),
                  title: 'Made For You',
                  subtitle: 'AI picks just for you',
                  icon: Icons.auto_awesome_rounded,
                  color: c1,
                  height: 130,
                  onTap: () => Navigator.push(outerCtx,
                      MaterialPageRoute(builder: (_) => const MadeForYouScreen())),
                ),
              ),
              const SizedBox(width: s8),
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_ai_shuffle'),
                  title: 'AI Shuffle',
                  subtitle: 'Smart queue, your taste',
                  icon: Icons.shuffle_rounded,
                  color: c2,
                  height: 130,
                  onTap: () => Navigator.push(outerCtx,
                      MaterialPageRoute(builder: (_) => const AiShuffleScreen())),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: s8),

        // Row 2 — shorter duo
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_favorites'),
                  title: 'Favorites',
                  subtitle: 'Your loved songs',
                  icon: Icons.favorite_rounded,
                  color: c3,
                  height: 100,
                  onTap: () => Navigator.push(outerCtx,
                      MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                ),
              ),
              const SizedBox(width: s8),
              Expanded(
                child: _ExploreCard(
                  key: const Key('explore_new_releases'),
                  title: 'New Releases',
                  subtitle: 'Fresh from the server',
                  icon: Icons.new_releases_rounded,
                  color: c4,
                  height: 100,
                  onTap: () => Navigator.push(outerCtx,
                      MaterialPageRoute(builder: (_) => const NewReleasesScreen())),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: s8),

        // Full-width Replay banner
        _ReplayBanner(
          key: const Key('explore_replay'),
          color: cReplay,
          onTap: () => Navigator.push(outerCtx,
              MaterialPageRoute(builder: (_) => const NavivibeReplayScreen())),
        ),
      ],
    );
  }
}

class _ExploreCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double height;
  final VoidCallback onTap;

  const _ExploreCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.height,
    required this.onTap,
  });

  @override
  State<_ExploreCard> createState() => _ExploreCardState();
}

class _ExploreCardState extends State<_ExploreCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final bg = t.isLight
        ? Color.alphaBlend(widget.color.withValues(alpha: 0.10), t.bgSurface)
        : Color.alphaBlend(widget.color.withValues(alpha: 0.14), t.bgBase);

    return Semantics(
      button: true,
      label: widget.title,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.height),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radiusLg,
              border: Border.all(
                color: widget.color.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Stack(
              children: [
                // Watermark
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: Icon(
                    widget.icon,
                    size: 90,
                    color: widget.color.withValues(alpha: 0.07),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Icon badge
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 17),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: t.textStyle(14, FontWeight.w700, t.textPrimary)
                                .copyWith(height: 1.2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: t.textStyle(11, FontWeight.w400, t.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Full-width Replay banner — distinct enough to stand out from the grid cards
class _ReplayBanner extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _ReplayBanner({super.key, required this.color, required this.onTap});

  @override
  State<_ReplayBanner> createState() => _ReplayBannerState();
}

class _ReplayBannerState extends State<_ReplayBanner> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final year = DateTime.now().year;
    final bg = t.isLight
        ? Color.alphaBlend(widget.color.withValues(alpha: 0.12), t.bgSurface)
        : Color.alphaBlend(widget.color.withValues(alpha: 0.16), t.bgBase);

    return Semantics(
      button: true,
      label: '$year Replay',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: Container(
            height: 76,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radiusLg,
              border: Border.all(
                color: widget.color.withValues(alpha: 0.22), width: 0.8),
            ),
            child: Stack(
              children: [
                // Large year text watermark
                Positioned(
                  right: -6,
                  top: -10,
                  child: Text(
                    '$year',
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w900,
                      color: widget.color.withValues(alpha: 0.06),
                      letterSpacing: -3,
                      height: 1,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.bar_chart_rounded,
                          color: widget.color, size: 19),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$year Replay',
                              style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: t.textPrimary),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Your year in music',
                              style: TextStyle(
                                fontSize: 11, color: t.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.color.withValues(alpha: 0.30),
                            width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View',
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: widget.color),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded,
                                size: 12, color: widget.color),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Recently Played Section
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
    final t = ThemeTokens.of(context);
    final selectedIdx = widget.tabController.index;
    final isDark = !t.isLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Pill-style tab switcher ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: s16),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: t.textPrimary.withValues(alpha: 0.06), width: 0.5),
            ),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final tabWidth = constraints.maxWidth / 2;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutQuart,
                      left: selectedIdx * tabWidth + 3,
                      width: tabWidth - 6,
                      top: 3, bottom: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.30),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: ['Albums', 'Tracks'].asMap().entries.map((e) {
                        final isActive = e.key == selectedIdx;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.tabController.animateTo(e.key),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? (t.isLight ? Colors.white : Colors.black)
                                      : t.textSecondary,
                                ),
                                child: Text(e.value),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Carousel ───────────────────────────────────────────────────
        SizedBox(
          height: 200,
          child: selectedIdx == 0
              ? _AlbumCarousel(albumsAsync: widget.albumsAsync)
              : _TrackCarousel(tracksAsync: widget.tracksAsync),
        ),
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
      error: (_, e) => const _EmptyCarouselHint(
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
          padding: const EdgeInsets.symmetric(horizontal: s16),
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

class _AlbumCard extends StatefulWidget {
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
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Play album: ${widget.album.name} by ${widget.album.artist}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 144,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: radiusMd,
                  child: SizedBox(
                    width: 144, height: 144,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.coverUrl != null)
                          CachedNetworkImage(
                            imageUrl: widget.coverUrl!,
                            cacheKey: 'cover_${widget.album.coverArt.isNotEmpty ? widget.album.coverArt : widget.album.id}',
                            fit: BoxFit.cover,
                            memCacheWidth: 288,
                            memCacheHeight: 288,
                            placeholder: (context, url) => _artPlaceholder(t),
                            errorWidget: (context, url, error) => _artPlaceholder(t),
                          )
                        else
                          _artPlaceholder(t),
                        // Bottom gradient for play button legibility
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 8, right: 8,
                          child: Container(
                            width: 32, height: 32,
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
                  widget.album.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textStyle(12, FontWeight.w700, t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.album.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textStyle(11, FontWeight.w400, t.textMuted),
                ),
              ],
            ),
          )
              .animate(delay: (widget.rank * 40).clamp(0, 200).ms)
              .fadeIn(duration: 350.ms)
              .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _artPlaceholder(AppThemeTokens t) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
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
      error: (_, e) => const _EmptyCarouselHint(
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
          padding: const EdgeInsets.symmetric(horizontal: s16),
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

class _TrackCard extends StatefulWidget {
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
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Play: ${widget.song.title} by ${widget.song.artist}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 134,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: radiusMd,
                  child: SizedBox(
                    width: 134, height: 134,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: widget.coverUrl,
                          cacheKey: 'cover_${widget.song.coverArt.isNotEmpty ? widget.song.coverArt : widget.song.id}',
                          fit: BoxFit.cover,
                          memCacheWidth: 268,
                          memCacheHeight: 268,
                          placeholder: (context, url) => _artPlaceholder(t),
                          errorWidget: (context, url, error) => _artPlaceholder(t),
                        ),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 7, right: 7,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.accent.withValues(alpha: 0.90),
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
                  widget.song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textStyle(12, FontWeight.w700, t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.song.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textStyle(11, FontWeight.w400, t.textMuted),
                ),
              ],
            ),
          )
              .animate(delay: (widget.rank * 40).clamp(0, 200).ms)
              .fadeIn(duration: 350.ms)
              .slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _artPlaceholder(AppThemeTokens t) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              t.accent.withValues(alpha: 0.5),
              t.accentDim.withValues(alpha: 0.20),
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
      padding: const EdgeInsets.symmetric(horizontal: s16),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: radiusMd,
          border: Border.all(color: t.outline, width: 0.8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: t.textMuted, size: 30),
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
// Quick Play Grid — 2-column playlist tiles
// =============================================================================

class _QuickPlayGrid extends StatelessWidget {
  final List<Playlist> items;
  final void Function(Playlist) onTap;
  const _QuickPlayGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();
    final t = ThemeTokens.of(context);

    // Six-step rotating palette aligned to the theme
    final palette = [
      t.accent,
      t.gold,
      Color.lerp(t.accent, t.gold, 0.5) ?? t.accent,
      Color.lerp(t.accent, t.bgElevated, 0.35) ?? t.accent,
      Color.lerp(t.gold, t.accentDim, 0.4) ?? t.gold,
      t.accentDim,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: s16),
      child: Column(
        children: [
          for (int r = 0; r < (items.length / 2).ceil(); r++)
            Padding(
              padding: const EdgeInsets.only(bottom: s8),
              child: Row(
                children: [
                  for (int c = 0; c < 2; c++)
                    Builder(builder: (_) {
                      final i = r * 2 + c;
                      if (i >= items.length) {
                        return const Expanded(child: SizedBox());
                      }
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: c == 1 ? s8 : 0),
                          child: _QuickTile(
                            playlist: items[i],
                            accentColor: palette[i % palette.length],
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
    final t = ThemeTokens.of(context);

    Widget tile = Semantics(
      button: true,
      label: 'Play playlist: ${playlist.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: radiusMd,
            border: Border.all(
              color: accentColor.withValues(alpha: 0.14), width: 0.8),
          ),
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              SizedBox(
                width: 58, height: 58,
                child: playlist.coverArt != null
                    ? CachedNetworkImage(
                        imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                        cacheKey: 'cover_${playlist.coverArt}',
                        fit: BoxFit.cover,
                        memCacheWidth: 116,
                        memCacheHeight: 116,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            accentColor.withValues(alpha: 0.8),
                            accentColor.withValues(alpha: 0.3),
                          ]),
                        ),
                        child: Icon(
                          Icons.queue_music_rounded,
                          color: t.textPrimary.withValues(alpha: 0.7),
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  playlist.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.textStyle(13, FontWeight.w600, t.textPrimary),
                ),
              ),
              Container(
                width: 28, height: 28,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    color: accentColor, size: 16),
              ),
            ],
          ),
        ),
      ),
    );

    return MediaQuery.of(context).disableAnimations
        ? tile
        : tile
            .animate(delay: (index * 40).clamp(0, 200).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

// =============================================================================
// Shimmer placeholders
// =============================================================================

class _ShimmerReel extends StatelessWidget {
  const _ShimmerReel();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: s16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: 144,
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: radiusMd,
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
