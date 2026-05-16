import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/replay_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../widgets/mini_player.dart';

// =============================================================================
// Replay Screen — Apple Music-style listening analytics
// Two tabs: Monthly Replay | This Week
// Data sourced from the Drift database (real SQLite listening events)
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
      value: ThemeTokens.of(context).isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
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
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _ReplayTabContent(
                        provider: monthlyReplayProvider,
                        periodLabel: _monthLabel(),
                        emptyLabel: 'Listen more this month to\nbuild your Monthly Replay',
                        showDailyChart: false,
                      ),
                      _ReplayTabContent(
                        provider: weeklyReplayProvider,
                        periodLabel: _weekLabel(),
                        emptyLabel: 'Listen more this week to\nbuild your Weekly Replay',
                        showDailyChart: true,
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
// Header — clean, no waveform decoration
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
      color: ThemeTokens.of(context).bgSurface,
      child: Column(
        children: [
          SizedBox(height: topPad + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Go back',
                  child: IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: ThemeTokens.of(context).textPrimary, size: 30),
                    onPressed: onBack,
                  ),
                ),
                const Spacer(),
                Text('Replay', style: ThemeTokens.of(context).headingSm),
                const Spacer(),
                SizedBox(width: 48),
              ],
            ),
          ),
          SizedBox(height: 8),
          TabBar(
            controller: tabController,
            labelColor: ThemeTokens.of(context).textPrimary,
            unselectedLabelColor: ThemeTokens.of(context).textMuted,
            indicatorColor: ThemeTokens.of(context).accent,
            indicatorWeight: 2,
            labelStyle: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(
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
// Tab content — showDailyChart gates the daily activity section
// =============================================================================

class _ReplayTabContent extends ConsumerWidget {
  final ProviderBase<AsyncValue<ReplayData>> provider;
  final String periodLabel;
  final String emptyLabel;
  final bool showDailyChart;

  const _ReplayTabContent({
    required this.provider,
    required this.periodLabel,
    required this.emptyLabel,
    required this.showDailyChart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(provider);

    return asyncData.when(
      data: (data) {
        if (data.isEmpty) return _EmptyReplay(label: emptyLabel);
        return _ReplayList(
          data: data,
          periodLabel: periodLabel,
          showDailyChart: showDailyChart,
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
            color: ThemeTokens.of(context).accent, strokeWidth: 2),
      ),
      error: (e, _) => Center(
        child: Text('Could not load replay data',
            style: TextStyle(color: ThemeTokens.of(context).textMuted)),
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
  final bool showDailyChart;

  const _ReplayList({
    required this.data,
    required this.periodLabel,
    required this.showDailyChart,
  });

  Future<void> _playSong(BuildContext context, WidgetRef ref, ReplaySong song) async {
    try {
      final svc = ref.read(subsonicServiceProvider);
      
      // If we are in the ranked list, we probably want to play the whole list 
      // starting from this song.
      final songIds = data.songs.map((s) => s.songId).toList();
      final startIndex = data.songs.indexOf(song);
      
      // Fetch full song objects for the queue
      final songs = await svc.getSongs(songIds);
      
      if (context.mounted && songs.isNotEmpty) {
        // Adjust index in case some songs failed to fetch
        int adjustedIndex = 0;
        final match = songs.indexWhere((s) => s.id == song.songId);
        if (match != -1) adjustedIndex = match;
        
        ref.read(playerProvider.notifier).setQueue(songs, adjustedIndex);
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

        // ── Daily chart — weekly tab only ─────────────────────────────
        if (showDailyChart)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _DailyListeningChart(dailyListening: data.dailyListening),
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
                    backgroundColor: ThemeTokens.of(context).accent,
                    foregroundColor: ThemeTokens.of(context).bgBase,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  icon: Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text('Play All',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: () async {
                    if (data.songs.isEmpty) return;
                    final svc = ref.read(subsonicServiceProvider);
                    final songIds = data.songs.map((s) => s.songId).toList();
                    final songs = await svc.getSongs(songIds);
                    if (context.mounted && songs.isNotEmpty) {
                      ref.read(playerProvider.notifier).setQueue(songs, 0);
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
            child: Text('Top Songs', style: ThemeTokens.of(context).headingSm),
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

        const SliverToBoxAdapter(child: SizedBox(height: 160)),
      ],
    );
  }
}

// =============================================================================
// Daily listening chart (weekly tab only)
// =============================================================================

class _DailyListeningChart extends StatelessWidget {
  final Map<int, int> dailyListening;
  const _DailyListeningChart({required this.dailyListening});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const double _maxBarHeight = 180.0;

  String _timeLabel(int sec) {
    if (sec <= 0) return '—';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final values = List.generate(7, (i) => dailyListening[i + 1] ?? 0);
    final maxVal = values.reduce((a, b) => a > b ? a : b).toDouble();
    final hasData = maxVal > 0;
    final avgSec = hasData ? values.reduce((a, b) => a + b) / 7 : 0.0;
    final today = DateTime.now().weekday;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: ThemeTokens.of(context).bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeTokens.of(context).outline, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('DAILY ACTIVITY',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: ThemeTokens.of(context).textMuted, letterSpacing: 1.2)),
              const Spacer(),
              if (hasData) ...[
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: ThemeTokens.of(context).accent.withOpacity(0.5),
                      shape: BoxShape.circle),
                ),
                SizedBox(width: 4),
                Text('avg ${_timeLabel(avgSec.round())}/day',
                    style: TextStyle(
                        fontSize: 11, color: ThemeTokens.of(context).textMuted,
                        fontWeight: FontWeight.w500)),
              ],
            ],
          ),
          SizedBox(height: 20),
          if (!hasData)
            SizedBox(
              height: _maxBarHeight + 40,
              child: Center(
                child: Text('No daily data yet — keep listening!',
                    style: TextStyle(
                        fontSize: 13,
                        color: ThemeTokens.of(context).textMuted.withOpacity(0.6))),
              ),
            )
          else
            SizedBox(
              height: _maxBarHeight + 60,
              child: LayoutBuilder(builder: (context, constraints) {
                final avgFraction =
                    maxVal > 0 ? (avgSec / maxVal).clamp(0.0, 1.0) : 0.0;
                final avgY = _maxBarHeight * (1 - avgFraction);

                return Stack(children: [
                  Positioned(
                    top: 20 + avgY,
                    left: 0,
                    right: 0,
                    child: _DashedLine(
                        color: ThemeTokens.of(context).accent.withOpacity(0.3)),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final sec = values[i];
                      final fraction = maxVal > 0
                          ? (sec / maxVal).clamp(0.05, 1.0)
                          : 0.05;
                      final isToday = (i + 1) == today;
                      final barGradient = isToday
                          ? [
                              ThemeTokens.of(context).accent,
                              ThemeTokens.of(context).accent.withOpacity(0.7),
                            ]
                          : [
                              HSLColor.fromAHSL(
                                      1.0, 160 + i * 4.0, 0.55, 0.38)
                                  .toColor(),
                              HSLColor.fromAHSL(
                                      1.0, 160 + i * 4.0, 0.45, 0.25)
                                  .toColor(),
                            ];

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: i == 0 ? 0 : 5,
                              right: i == 6 ? 0 : 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                _timeLabel(sec),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? ThemeTokens.of(context).accent
                                      : ThemeTokens.of(context).textMuted,
                                ),
                              ),
                              SizedBox(height: 4),
                              TweenAnimationBuilder<double>(
                                tween: Tween(
                                    begin: 0.0,
                                    end: _maxBarHeight * fraction),
                                duration: Duration(
                                    milliseconds: 600 + i * 80),
                                curve: Curves.easeOutCubic,
                                builder: (context, height, _) {
                                  return Container(
                                    height: height,
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: barGradient,
                                      ),
                                      boxShadow: isToday
                                          ? [
                                              BoxShadow(
                                                color: AppTheme
                                                    .spotifyGreen
                                                    .withOpacity(0.3),
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: 8),
                              Text(
                                _dayLabels[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isToday
                                      ? ThemeTokens.of(context).accent
                                      : ThemeTokens.of(context).textSecondary,
                                ),
                              ),
                              if (isToday)
                                Container(
                                  margin: const EdgeInsets.only(top: 3),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: ThemeTokens.of(context).accent,
                                      shape: BoxShape.circle),
                                )
                              else
                                SizedBox(height: 7),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ]);
              }),
            ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final dashCount = (constraints.maxWidth / 8).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
            dashCount, (_) => Container(width: 4, height: 1, color: color)),
      );
    });
  }
}

// =============================================================================
// Stats card — hero listening time + side counts + genre pill
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
        color: ThemeTokens.of(context).bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeTokens.of(context).outline, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: label + genre pill
          Row(
            children: [
              Text('YOUR REPLAY',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: ThemeTokens.of(context).accent, letterSpacing: 1.5)),
              const Spacer(),
              if (stats.topGenre != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeTokens.of(context).accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: ThemeTokens.of(context).accent.withOpacity(0.25),
                        width: 0.7),
                  ),
                  child: Text(
                    stats.topGenre!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ThemeTokens.of(context).accent),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(periodLabel, style: ThemeTokens.of(context).headingMd),
          SizedBox(height: 20),

          // Hero row: big time | divider | stacked counts
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Large listening time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stats.totalTimeLabel,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: ThemeTokens.of(context).textPrimary,
                        letterSpacing: -1.5,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'time listened',
                      style: TextStyle(
                          fontSize: 12,
                          color: ThemeTokens.of(context).textMuted,
                          fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),

              // Thin divider
              Container(
                width: 0.7,
                height: 52,
                margin: const EdgeInsets.only(right: 16),
                color: ThemeTokens.of(context).outline,
              ),

              // Songs + artists stacked
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InlineStatRow(
                    icon: Icons.music_note_rounded,
                    value: '${stats.uniqueSongs}',
                    label: 'songs',
                  ),
                  SizedBox(height: 10),
                  _InlineStatRow(
                    icon: Icons.person_outline_rounded,
                    value: '${stats.uniqueArtists}',
                    label: 'artists',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineStatRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _InlineStatRow(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: ThemeTokens.of(context).textMuted),
        SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ThemeTokens.of(context).textPrimary)),
        SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: ThemeTokens.of(context).textMuted)),
      ],
    );
  }
}

// =============================================================================
// Ranked song row
// =============================================================================

class _ReplaySongRow extends ConsumerWidget {
  final ReplaySong song;
  final int rank;
  final VoidCallback onTap;
  const _ReplaySongRow(
      {required this.song, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final coverUrl =
        song.coverArtId != null ? svc.getCoverArtUrl(song.coverArtId!) : null;

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
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rank <= 3 ? 20 : 15,
                    fontWeight: FontWeight.w900,
                    color:
                        rank <= 3 ? ThemeTokens.of(context).accent : ThemeTokens.of(context).textMuted,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: ThemeTokens.of(context).bgElevated),
                clipBehavior: Clip.hardEdge,
                child: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheKey: 'replay_${song.songId}',
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _artPlaceholder(context),
                        errorWidget: (_, __, ___) => _artPlaceholder(context),
                      )
                    : _artPlaceholder(context),
              ),
              SizedBox(width: 12),
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
                              ? ThemeTokens.of(context).textPrimary
                              : ThemeTokens.of(context).textPrimary.withOpacity(0.85),
                        )),
                    SizedBox(height: 2),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: ThemeTokens.of(context).textSecondary)),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    song.listeningLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: rank <= 3
                          ? ThemeTokens.of(context).accent
                          : ThemeTokens.of(context).textMuted,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text('${song.playCount} plays',
                      style: TextStyle(
                          fontSize: 10, color: ThemeTokens.of(context).textMuted)),
                ],
              ),
              SizedBox(width: 4),
              Icon(Icons.play_circle_outline_rounded,
                  color: ThemeTokens.of(context).textMuted.withOpacity(0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artPlaceholder(BuildContext context) => Container(
        color: ThemeTokens.of(context).bgElevated,
        child: Icon(Icons.music_note_rounded,
            color: ThemeTokens.of(context).textMuted, size: 20),
      );
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ThemeTokens.of(context).accent.withOpacity(0.12),
            ),
            child: Icon(Icons.bar_chart_rounded,
                color: ThemeTokens.of(context).accent, size: 40),
          ),
          SizedBox(height: 20),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ThemeTokens.of(context).textSecondary, fontSize: 15, height: 1.5)),
        ],
      )
          .animate()
          .fadeIn(duration: 500.ms)
          .scale(
              begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
    );
  }
}