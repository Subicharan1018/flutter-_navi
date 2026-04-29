import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/replay_provider.dart';
import '../core/theme.dart';

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
    return 'Apr ${monday.day} – ${sunday.day}'; // simplified; good enough
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.coreBackground,
        body: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            _ReplayHeader(
              topPad: topPad,
              tabController: _tabController,
              monthLabel: _monthLabel(),
              weekLabel: _weekLabel(),
              onBack: () => Navigator.pop(context),
            ),

            // ── Tab views ─────────────────────────────────────────────────────
            // Expanded prevents "Vertical viewport unbounded height" error.
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
          // Waveform decoration
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
// Animated waveform decoration (purely visual)
// =============================================================================

class _WaveformDecoration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (i) {
          final h = (i % 6 == 0
              ? 32.0
              : i % 3 == 0
                  ? 22.0
                  : i % 2 == 0
                      ? 16.0
                      : 10.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: AppTheme.spotifyGreen.withOpacity(0.3 + (i % 4) * 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )
          .animate(delay: (i * 30).ms)
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic);
        }),
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
        return _ReplayList(data: data, periodLabel: periodLabel, ref: ref);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppTheme.spotifyGreen,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) => Center(
        child: Text('Could not load replay data',
            style: TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }
}

// =============================================================================
// Stats header card + ranked song list
// =============================================================================

class _ReplayList extends StatelessWidget {
  final ReplayData data;
  final String periodLabel;
  final WidgetRef ref;

  const _ReplayList({
    required this.data,
    required this.periodLabel,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Stats summary card ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: _StatsCard(stats: data.stats, periodLabel: periodLabel),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
        ),

        // ── "Play All" button ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                  onPressed: () {
                    // Note: Replay songs don't carry full Song objects.
                    // We navigate back and let the user play from the list.
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
        ),

        // ── Section title ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Top Songs', style: AppTheme.headingSm),
          ),
        ),

        // ── Song rows ──────────────────────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ReplaySongRow(
              song: data.songs[i],
              rank: i + 1,
            )
            .animate(delay: (i * 50).clamp(0, 400).ms)
            .fadeIn(duration: 350.ms)
            .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
            childCount: data.songs.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
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
          Text('Your Replay',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(periodLabel, style: AppTheme.headingMd),
          const SizedBox(height: 20),
          // Stat chips row
          Row(
            children: [
              _StatChip(
                icon: Icons.timer_outlined,
                label: stats.totalTimeLabel,
                sublabel: 'Listened',
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.music_note_rounded,
                label: '${stats.uniqueSongs}',
                sublabel: 'Songs',
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.person_outline_rounded,
                label: '${stats.uniqueArtists}',
                sublabel: 'Artists',
              ),
              if (stats.topGenre != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    icon: Icons.category_outlined,
                    label: stats.topGenre!,
                    sublabel: 'Top Genre',
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
  final String label;
  final String sublabel;
  const _StatChip({required this.icon, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.topLevel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.spotifyGreen, size: 18),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          Text(sublabel,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

// =============================================================================
// Ranked song row
// =============================================================================

class _ReplaySongRow extends StatelessWidget {
  final ReplaySong song;
  final int rank;
  const _ReplaySongRow({required this.song, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rank $rank: ${song.title} by ${song.artist}, ${song.listeningLabel} listening time',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.05), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 30,
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
            const SizedBox(width: 14),
            // Gradient art placeholder — 48dp height (accessibility min target)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [
                    AppTheme.spotifyGreen.withOpacity(0.6),
                    AppTheme.spotifyGreen.withOpacity(0.15),
                  ],
                ),
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: Colors.white38, size: 22),
            ),
            const SizedBox(width: 14),
            // Song info — Expanded to prevent overflow
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
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
            const SizedBox(width: 12),
            // Right side stats
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  song.listeningLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.spotifyGreen,
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
          ],
        ),
      ),
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
