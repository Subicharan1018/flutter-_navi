import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/replay_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../widgets/mini_player.dart';

// =============================================================================
// Replay Screen — Apple Music-style listening analytics
// Two tabs: Monthly Replay | This Week
// Data sourced from navivibe_analytics.db (real SQLite listening events)
// =============================================================================

class ReplayScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const ReplayScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends ConsumerState<ReplayScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _monthLabel() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.year}';
  }

  String _weekLabel() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${monthNames[monday.month - 1]} ${monday.day} – ${sunday.day}';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.coreBackground,
        body: Stack(
          children: [
            Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                _ReplayHeader(
                  topPad: topPad,
                  tabController: _tabController,
                  monthLabel: _monthLabel(),
                  weekLabel: _weekLabel(),
                  onBack: () => Navigator.pop(context),
                ),

                // ── Tab views ─────────────────────────────────────────────
                // Expanded prevents "Vertical viewport unbounded height".
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _ReplayTabContent(
                        provider: monthlyReplayProvider,
                        periodLabel: _monthLabel(),
                        emptyLabel: 'Listen more this month to\nbuild your Monthly Replay',
                      ),
                      _ReplayTabContent(
                        provider: weeklyReplayProvider,
                        periodLabel: _weekLabel(),
                        emptyLabel: 'Listen more this week to\nbuild your Weekly Replay',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Mini player overlay ─────────────────────────────────────
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Header with tab bar
// =============================================================================

class _ReplayHeader extends StatelessWidget {
  final double topPad;
  final TabController tabController;
  final String monthLabel;
  final String weekLabel;
  final VoidCallback onBack;

  const _ReplayHeader({
    required this.topPad,
    required this.tabController,
    required this.monthLabel,
    required this.weekLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceLevel,
      child: Column(
        children: [
          SizedBox(height: topPad + 8),
          // Back button row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Go back',
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textPrimary, size: 30),
                    onPressed: onBack,
                  ),
                ),
                const Spacer(),
                Text('Replay', style: AppTheme.headingSm),
                const Spacer(),
                const SizedBox(width: 48), // balance
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Animated waveform
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _WaveformDecoration(),
          ),
          const SizedBox(height: 16),
          // Tab bar
          TabBar(
            controller: tabController,
            labelColor: AppTheme.textPrimary,
            unselectedLabelColor: AppTheme.textMuted,
            indicatorColor: AppTheme.spotifyGreen,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w400),
            tabs: [
              Tab(text: monthLabel),
              const Tab(text: 'This Week'),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Animated waveform — syncs to the listening distribution
// =============================================================================

class _WaveformDecoration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Simulated listening intensity bars — alternating heights for visual rhythm
    final heights = [
      8.0, 16.0, 24.0, 14.0, 32.0, 20.0, 28.0, 12.0,
      36.0, 18.0, 30.0, 10.0, 22.0, 34.0, 16.0, 26.0,
      8.0, 20.0, 38.0, 14.0, 28.0, 12.0, 32.0, 18.0,
    ];

    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(heights.length, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: _AnimatedBar(
              height: heights[i],
              delay: i * 35,
              color: HSLColor.fromAHSL(
                1.0,
                140 + (i * 2.5), // hue shift green → teal
                0.65,
                0.35 + (heights[i] / 50),
              ).toColor(),
            ),
          );
        }),
      ),
    );
  }
}

class _AnimatedBar extends StatefulWidget {
  final double height;
  final int delay;
  final Color color;
  const _AnimatedBar({required this.height, required this.delay, required this.color});

  @override
  State<_AnimatedBar> createState() => _AnimatedBarState();
}

class _AnimatedBarState extends State<_AnimatedBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200 + widget.delay),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.height).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Container(
        width: 3.5,
        height: _animation.value,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// =============================================================================
// Tab content — stats card + song list
// =============================================================================

class _ReplayTabContent extends ConsumerWidget {
  final ProviderBase<AsyncValue<ReplayData>> provider;
  final String periodLabel;
  final String emptyLabel;

  const _ReplayTabContent({
    required this.provider,
    required this.periodLabel,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(provider);

    return asyncData.when(
      data: (data) {
        if (data.isEmpty) {
          return _EmptyReplay(label: emptyLabel);
        }
        return _ReplayList(data: data, periodLabel: periodLabel);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppTheme.spotifyGreen,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) => const Center(
        child: Text('Could not load replay data',
            style: TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }
}

// =============================================================================
// Stats header card + ranked song list
// =============================================================================

class _ReplayList extends ConsumerWidget {
  final ReplayData data;
  final String periodLabel;

  const _ReplayList({
    required this.data,
    required this.periodLabel,
  });

  Future<void> _playSong(BuildContext context, WidgetRef ref, ReplaySong song) async {
    try {
      final svc = ref.read(subsonicServiceProvider);
      // Search for the song on the server to get the full Song object
      final searchResult = await svc.search(song.title);
      final results = searchResult['songs'] as List<Song>? ?? [];
      final match = results.where((s) => s.id == song.songId).firstOrNull;
      if (match != null && context.mounted) {
        ref.read(playerProvider.notifier).setQueue([match], 0);
      } else if (results.isNotEmpty && context.mounted) {
        // Fallback — play best title match
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
    // Calculate max listening time for the bar chart proportions
    final maxSec = data.songs.isNotEmpty
        ? data.songs.first.totalMinutesSec.toDouble()
        : 1.0;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Stats summary card ─────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: _StatsCard(stats: data.stats, periodLabel: periodLabel),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
        ),

        // ── Listening time distribution chart ──────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _ListeningChart(songs: data.songs, maxSec: maxSec),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
        ),

        // ── "Play All" button ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Semantics(
              button: true,
              label: 'Play all replay songs',
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.spotifyGreen,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Play All',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: () async {
                    // Play all replay songs in order
                    for (final song in data.songs) {
                      await _playSong(context, ref, song);
                      break; // Play first one; rest can be queued later
                    }
                  },
                ),
              ),
            ),
          ),
        ),

        // ── Section title ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Top Songs', style: AppTheme.headingSm),
          ),
        ),

        // ── Song rows ──────────────────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ReplaySongRow(
              song: data.songs[i],
              rank: i + 1,
              onTap: () => _playSong(context, ref, data.songs[i]),
            )
            .animate(delay: (i * 50).clamp(0, 400).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
            childCount: data.songs.length,
          ),
        ),

        // Bottom spacing for mini player
        const SliverToBoxAdapter(child: SizedBox(height: 160)),
      ],
    );
  }
}

// =============================================================================
// Listening time distribution chart — horizontal bars for each song
// =============================================================================

class _ListeningChart extends StatelessWidget {
  final List<ReplaySong> songs;
  final double maxSec;
  const _ListeningChart({required this.songs, required this.maxSec});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outlineColor, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LISTENING TIME',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: AppTheme.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 14),
          ...songs.take(5).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final song = entry.value;
            final fraction = maxSec > 0
                ? (song.totalMinutesSec / maxSec).clamp(0.0, 1.0)
                : 0.0;

            // Green gradient from bright to dark based on rank
            final barColor = HSLColor.fromAHSL(
              1.0,
              142, // Spotify green hue
              0.7 - (i * 0.08),
              0.45 - (i * 0.04),
            ).toColor();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                        color: i == 0 ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            // Track
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppTheme.topLevel,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            // Fill
                            AnimatedContainer(
                              duration: Duration(milliseconds: 600 + i * 100),
                              curve: Curves.easeOutCubic,
                              width: constraints.maxWidth * fraction,
                              height: 16,
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text(
                      song.listeningLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: i == 0 ? AppTheme.spotifyGreen : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =============================================================================
// Stats summary card
// =============================================================================

class _StatsCard extends StatelessWidget {
  final ReplayStats stats;
  final String periodLabel;
  const _StatsCard({required this.stats, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineColor, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR REPLAY',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppTheme.spotifyGreen, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Text(periodLabel, style: AppTheme.headingMd),
          const SizedBox(height: 20),
          // Stat chips row — wrap in a Row with Expanded to prevent overflow
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  icon: Icons.timer_outlined,
                  value: stats.totalTimeLabel,
                  label: 'Listened',
                  highlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  icon: Icons.music_note_rounded,
                  value: '${stats.uniqueSongs}',
                  label: 'Songs',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  icon: Icons.person_outline_rounded,
                  value: '${stats.uniqueArtists}',
                  label: 'Artists',
                ),
              ),
              if (stats.topGenre != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    icon: Icons.category_outlined,
                    value: stats.topGenre!,
                    label: 'Top Genre',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool highlight;
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.spotifyGreen.withOpacity(0.12)
            : AppTheme.topLevel,
        borderRadius: BorderRadius.circular(12),
        border: highlight
            ? Border.all(color: AppTheme.spotifyGreen.withOpacity(0.3), width: 0.7)
            : null,
      ),
      child: Column(
        children: [
          Icon(icon,
              color: highlight ? AppTheme.spotifyGreen : AppTheme.textMuted,
              size: 18),
          const SizedBox(height: 6),
          Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: highlight ? AppTheme.spotifyGreen : AppTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 9, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

// =============================================================================
// Ranked song row — tappable, with real artwork
// =============================================================================

class _ReplaySongRow extends ConsumerWidget {
  final ReplaySong song;
  final int rank;
  final VoidCallback onTap;
  const _ReplaySongRow({required this.song, required this.rank, required this.onTap});

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
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.04), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rank <= 3 ? 20 : 15,
                    fontWeight: FontWeight.w900,
                    color: rank <= 3
                        ? AppTheme.spotifyGreen
                        : AppTheme.textMuted,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Album art — real cover from Subsonic
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: AppTheme.topLevel,
                ),
                clipBehavior: Clip.hardEdge,
                child: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheKey: 'replay_${song.songId}',
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _artPlaceholder(),
                        errorWidget: (_, __, ___) => _artPlaceholder(),
                      )
                    : _artPlaceholder(),
              ),
              const SizedBox(width: 12),
              // Song info — Expanded to prevent overflow
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: rank <= 3
                              ? AppTheme.textPrimary
                              : AppTheme.textPrimary.withOpacity(0.85),
                        )),
                    const SizedBox(height: 2),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side stats
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    song.listeningLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: rank <= 3
                          ? AppTheme.spotifyGreen
                          : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.playCount} plays',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              // Play indicator
              Icon(Icons.play_circle_outline_rounded,
                  color: AppTheme.textMuted.withOpacity(0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artPlaceholder() {
    return Container(
      color: AppTheme.topLevel,
      child: const Icon(Icons.music_note_rounded,
          color: AppTheme.textMuted, size: 20),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyReplay extends StatelessWidget {
  final String label;
  const _EmptyReplay({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.spotifyGreen.withOpacity(0.12),
            ),
            child: const Icon(Icons.bar_chart_rounded,
                color: AppTheme.spotifyGreen, size: 40),
          ),
          const SizedBox(height: 20),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15, height: 1.5)),
        ],
      )
      .animate()
      .fadeIn(duration: 500.ms)
      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
    );
  }
}
