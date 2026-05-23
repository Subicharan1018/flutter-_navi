import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/listening_stats.dart';
import '../providers/listening_stats_provider.dart';
import '../providers/settings_provider.dart';

// =============================================================================
// ListeningStatsScreen
//
// Displays playback stats fetched from the FastAPI listening-log server.
// Period selector (Weekly / Monthly / All-time) at the top; data in a
// scrollable body with summary cards, ranked lists and recent plays.
// =============================================================================

class ListeningStatsScreen extends ConsumerStatefulWidget {
  const ListeningStatsScreen({super.key});

  @override
  ConsumerState<ListeningStatsScreen> createState() =>
      _ListeningStatsScreenState();
}

class _ListeningStatsScreenState extends ConsumerState<ListeningStatsScreen>
    with SingleTickerProviderStateMixin {
  String _period = 'weekly';

  static const _periods = ['weekly', 'monthly', 'all'];
  static const _periodLabels = {
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'all': 'All Time',
  };

  void _refresh() {
    ref.read(listeningStatsProvider(_period).notifier).fetch();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final loggingUrl = ref.watch(settingsProvider).loggingApiUrl;
    final statsAsync = ref.watch(listeningStatsProvider(_period));

    return Scaffold(
      backgroundColor: tokens.bgBase,
      appBar: AppBar(
        backgroundColor: tokens.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: tokens.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          'Listening Stats',
          style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded,
                  color: tokens.textMuted, size: 22),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Period selector ──────────────────────────────────────────────
          _PeriodSelector(
            selected: _period,
            onChanged: (p) => setState(() => _period = p),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: loggingUrl.isEmpty
                ? _EmptyConfigState(tokens: tokens)
                : statsAsync.when(
                    loading: () => _SkeletonLoader(tokens: tokens),
                    error: (e, _) =>
                        _ErrorState(message: e.toString(), onRetry: _refresh),
                    data: (stats) => _StatsBody(stats: stats),
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Period selector
// =============================================================================

class _PeriodSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  static const _periods = ['weekly', 'monthly', 'all'];
  static const _labels = {
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'all': 'All Time',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceOpaque,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.outline),
      ),
      child: Row(
        children: _periods.map((p) {
          final isActive = p == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isActive ? tokens.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _labels[p]!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive
                        ? (tokens.isLight ? Colors.white : Colors.black)
                        : tokens.textMuted,
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
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
// Main stats body — RefreshIndicator + CustomScrollView
// =============================================================================

class _StatsBody extends StatelessWidget {
  final ListeningStats stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Consumer(
      builder: (context, ref, _) {
        final period =
            (context.findAncestorStateOfType<_ListeningStatsScreenState>()
                    ?._period) ??
                'weekly';
        return RefreshIndicator(
          color: tokens.accent,
          backgroundColor: tokens.bgSurfaceOpaque,
          onRefresh: () async {
            ref.read(listeningStatsProvider(period).notifier).fetch();
            // Brief artificial delay so the spinner is visible
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Period label ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    stats.label,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // ── Summary cards ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.play_circle_outline_rounded,
                          label: 'Total Plays',
                          value: '${stats.totalPlays}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.timer_outlined,
                          label: 'Minutes',
                          value: _formatMinutes(stats.totalMinutes),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Top Artists ──────────────────────────────────────────────
              if (stats.topArtists.isNotEmpty) ...[
                _SectionHeader(title: 'TOP ARTISTS'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _RankedRow(
                        rank: i + 1,
                        title: stats.topArtists[i].artist,
                        subtitle:
                            '${stats.topArtists[i].playCount} plays',
                      ),
                      childCount: stats.topArtists.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],

              // ── Top Tracks ───────────────────────────────────────────────
              if (stats.topTracks.isNotEmpty) ...[
                _SectionHeader(title: 'TOP TRACKS'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _RankedRow(
                        rank: i + 1,
                        title: stats.topTracks[i].title,
                        subtitle:
                            '${stats.topTracks[i].artist} · ${stats.topTracks[i].playCount} plays',
                      ),
                      childCount: stats.topTracks.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],

              // ── Recent Plays ─────────────────────────────────────────────
              if (stats.recentPlays.isNotEmpty) ...[
                _SectionHeader(title: 'RECENTLY PLAYED'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) =>
                          _RecentPlayRow(play: stats.recentPlays[i]),
                      childCount: stats.recentPlays.length,
                    ),
                  ),
                ),
              ],

              // Bottom padding for mini-player
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        );
      },
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// =============================================================================
// Summary stat card
// =============================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceOpaque,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.accent, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(
          title,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Ranked row (artists / tracks)
// =============================================================================

class _RankedRow extends StatelessWidget {
  final int rank;
  final String title;
  final String subtitle;

  const _RankedRow({
    required this.rank,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    // Accent fades for lower ranks: rank 1 = full accent, rank 5+ = muted
    final badgeOpacity = max(0.2, 1.0 - (rank - 1) * 0.18);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceOpaque,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.outline),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: badgeOpacity * 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: tokens.accent.withValues(alpha: badgeOpacity),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: tokens.textMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
// Recent play row — cover art thumbnail + time ago
// =============================================================================

class _RecentPlayRow extends StatelessWidget {
  final RecentPlay play;
  const _RecentPlayRow({required this.play});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceOpaque,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.outline),
      ),
      child: Row(
        children: [
          // Cover art
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: play.coverArt != null && play.coverArt!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: play.coverArt!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _PlaceholderCover(tokens: tokens),
                  )
                : _PlaceholderCover(tokens: tokens),
          ),
          const SizedBox(width: 12),
          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  play.title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  play.artist,
                  style: TextStyle(
                      color: tokens.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Time ago
          Text(
            play.timeAgo,
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  final AppThemeTokens tokens;
  const _PlaceholderCover({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: tokens.bgElevated,
      child: Icon(Icons.music_note_rounded,
          color: tokens.textMuted, size: 22),
    );
  }
}

// =============================================================================
// Loading skeleton
// =============================================================================

class _SkeletonLoader extends StatefulWidget {
  final AppThemeTokens tokens;
  const _SkeletonLoader({required this.tokens});

  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.75).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final shimmer = t.bgSurface.withValues(alpha: _anim.value);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Summary cards
            Row(
              children: [
                Expanded(child: _SkeletonBox(color: shimmer, height: 90)),
                const SizedBox(width: 12),
                Expanded(child: _SkeletonBox(color: shimmer, height: 90)),
              ],
            ),
            const SizedBox(height: 24),
            _SkeletonBox(color: shimmer, height: 14, width: 100),
            const SizedBox(height: 10),
            ...List.generate(
                4, (_) => _SkeletonBox(color: shimmer, height: 52, bottomPad: 8)),
            const SizedBox(height: 16),
            _SkeletonBox(color: shimmer, height: 14, width: 100),
            const SizedBox(height: 10),
            ...List.generate(
                4, (_) => _SkeletonBox(color: shimmer, height: 52, bottomPad: 8)),
          ],
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final Color color;
  final double height;
  final double? width;
  final double bottomPad;

  const _SkeletonBox({
    required this.color,
    required this.height,
    this.width,
    this.bottomPad = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// =============================================================================
// Error state
// =============================================================================

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                color: tokens.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not load stats',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style:
                  TextStyle(color: tokens.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
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
// Empty config state — shown when uploadApiUrl is not set
// =============================================================================

class _EmptyConfigState extends StatelessWidget {
  final AppThemeTokens tokens;
  const _EmptyConfigState({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_ethernet_rounded,
                color: tokens.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              'No Server Configured',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set a Custom API URL in Settings → Advanced Upload to enable listening stats.',
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
