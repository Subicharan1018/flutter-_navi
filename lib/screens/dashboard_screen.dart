import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

import '../core/theme.dart';
import '../widgets/navi_ui.dart';
import '../widgets/contribution_graph.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../features/ai_shuffle/data/models/model_status_response.dart';

enum StatsPeriod { weekly, monthly, all }

extension StatsPeriodValue on StatsPeriod {
  String get value => toString().split('.').last;
  String get label {
    switch (this) {
      case StatsPeriod.weekly:
        return '7 Days';
      case StatsPeriod.monthly:
        return '30 Days';
      case StatsPeriod.all:
        return 'All Time';
    }
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  StatsPeriod _period = StatsPeriod.weekly;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(listeningStatsProvider(_period.value));
    final modelAsync = ref.watch(modelStatusProvider);
    final tokens = ThemeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(listeningStatsProvider(_period.value));
          ref.invalidate(modelStatusProvider);
          ref.invalidate(contributionGraphProvider);
        },
        color: tokens.accent,
        backgroundColor: tokens.bgElevated,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 130,
              pinned: true,
              backgroundColor: tokens.bgBase,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.zero,
                expandedTitleScale: 1.0,
                title: LayoutBuilder(
                  builder: (_, constraints) {
                    final isCollapsed = constraints.maxHeight < 72;
                    return Container(
                      alignment: Alignment.bottomLeft,
                      padding: EdgeInsets.fromLTRB(
                        s16,
                        0,
                        s16,
                        isCollapsed ? 14 : s16,
                      ),
                      child: isCollapsed
                          ? _CollapsedHeader(tokens: tokens, period: _period)
                          : _ExpandedHeader(tokens: tokens),
                    );
                  },
                ),
              ),
            ),

            // ── Period Tabs ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(s16, s8, s16, 0),
                child: _PeriodSelector(
                  selected: _period,
                  onChanged: (p) => setState(() => _period = p),
                ),
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            statsAsync.when(
              data: (stats) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(s16, s20, s16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Metrics
                    _MetricsRow(stats: stats, tokens: tokens),
                    const SizedBox(height: s24),

                    HourlyHeatmap(heatmapData: stats.hourlyHeatmap),
                    const SizedBox(height: s24),

                    GenreRadarChart(genres: stats.genreBreakdown),
                    const SizedBox(height: s24),

                    const ContributionGraphCard(),
                    const SizedBox(height: s24),

                    ListeningLineChart(
                      spots: _buildLineSpots(stats),
                      labels: _buildLineLabels(stats),
                    ),
                    const SizedBox(height: s24),

                    _Label(text: 'Top artists', tokens: tokens),
                    const SizedBox(height: s12),
                    _TopArtistsList(artists: stats.topArtists),
                    const SizedBox(height: s24),

                    _Label(text: 'Top tracks', tokens: tokens),
                    const SizedBox(height: s12),
                    _TopTracksList(tracks: stats.topTracks),
                    const SizedBox(height: s24),

                    modelAsync.when(
                      data: (m) => ModelStatusCard(status: m),
                      loading: () => const NaviSkeleton(height: 140),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 48),
                  ]),
                ),
              ),
              loading: () => SliverPadding(
                padding: const EdgeInsets.all(s16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const NaviSkeleton(height: 100),
                    const SizedBox(height: s16),
                    const NaviSkeleton(height: 180),
                    const SizedBox(height: s16),
                    const NaviSkeleton(height: 220),
                  ]),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: tokens.textMuted,
                        size: 36,
                      ),
                      const SizedBox(height: s16),
                      Text(
                        'Could not load stats',
                        style: TextStyle(
                          fontSize: 15,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: s12),
                      LiquidGlassButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        onTap: () => ref.invalidate(
                          listeningStatsProvider(_period.value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _buildLineSpots(ListeningStatsResponse stats) {
    final now = DateTime.now();
    final map = <String, int>{};
    for (int i = 29; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      map[key] = 0;
    }
    for (final play in stats.recentPlays) {
      final playedAt = play['played_at_ist']?.toString() ?? '';
      if (playedAt.length >= 10) {
        final date = playedAt.substring(0, 10);
        if (map.containsKey(date)) map[date] = map[date]! + 1;
      }
    }
    final sortedKeys = map.keys.toList()..sort();
    return List.generate(
      sortedKeys.length,
      (i) => FlSpot(i.toDouble(), map[sortedKeys[i]]!.toDouble()),
    );
  }

  List<String> _buildLineLabels(ListeningStatsResponse stats) {
    final now = DateTime.now();
    return List.generate(30, (i) {
      final d = now.subtract(Duration(days: 29 - i));
      return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final AppThemeTokens tokens;
  const _Label({required this.text, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
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
            color: tokens.textPrimary.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}

class _CollapsedHeader extends StatelessWidget {
  final AppThemeTokens tokens;
  final StatsPeriod period;
  const _CollapsedHeader({required this.tokens, required this.period});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: tokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: s8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.accent.withValues(alpha: 0.4), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            period.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: tokens.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final AppThemeTokens tokens;
  const _ExpandedHeader({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listening intelligence',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: tokens.textMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: tokens.textPrimary,
            letterSpacing: -0.8,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

// ── Period Selector ───────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onChanged;
  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Row(
      children: StatsPeriod.values.map((p) {
        final isSelected = p == selected;
        return Padding(
          padding: const EdgeInsets.only(right: s8),
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: kAnimNormal,
              padding: const EdgeInsets.symmetric(horizontal: s16, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accent : Colors.transparent,
                borderRadius: radiusFull,
                border: Border.all(
                  color: isSelected ? tokens.accent : tokens.outline,
                  width: 1,
                ),
              ),
              child: Text(
                p.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? tokens.bgBase : tokens.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Metrics Row ───────────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  final ListeningStatsResponse stats;
  final AppThemeTokens tokens;
  const _MetricsRow({required this.stats, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final skipRate = (stats.skipRate * 100).toInt();
    Color skipColor = tokens.accent;
    if (skipRate > 20) {
      skipColor = Theme.of(context).colorScheme.error;
    } else if (skipRate >= 10)
      skipColor = const Color(0xFFFFD700);

    return Column(
      children: [
        // ── Primary pair: big editorial numbers ────────────────────────
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _BigMetric(
                  value: stats.totalPlays,
                  label: 'Plays',
                  accent: tokens.accent,
                  tokens: tokens,
                ),
              ),
              Container(
                width: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: tokens.textPrimary.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _BigMetric(
                  value: stats.totalMinutes,
                  label: 'Minutes',
                  accent: const Color(0xFF64D2FF),
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: tokens.textPrimary.withValues(alpha: 0.08)),
        // ── Secondary pair ──────────────────────────────────────────────
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _SmallMetric(
                  value: '$skipRate%',
                  label: 'Skip rate',
                  valueColor: skipColor,
                  tokens: tokens,
                ),
              ),
              Container(
                width: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: tokens.textPrimary.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _SmallMetric(
                  value: stats.streakDays > 3
                      ? '${stats.streakDays} 🔥'
                      : '${stats.streakDays}d',
                  label: 'Streak',
                  valueColor: stats.streakDays > 3
                      ? const Color(0xFF1DB954)
                      : tokens.textPrimary,
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigMetric extends StatelessWidget {
  final int value;
  final String label;
  final Color accent;
  final AppThemeTokens tokens;
  const _BigMetric({
    required this.value,
    required this.label,
    required this.accent,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 2,
            decoration: BoxDecoration(color: accent, borderRadius: radiusFull),
          ),
          const SizedBox(height: s8),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => Text(
              _fmt(val),
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: tokens.textPrimary,
                letterSpacing: -1.0,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: tokens.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return v.toString();
  }
}

class _SmallMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final AppThemeTokens tokens;
  const _SmallMetric({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: valueColor,
              letterSpacing: -1.0,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: tokens.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hourly Heatmap ────────────────────────────────────────────────────────────

class HourlyHeatmap extends StatelessWidget {
  final Map<String, int> heatmapData;
  const HourlyHeatmap({super.key, required this.heatmapData});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final maxCount = heatmapData.values.fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    int peakHour = 0;
    heatmapData.forEach((hour, count) {
      if (count == maxCount) peakHour = int.parse(hour);
    });
    final amPm = peakHour >= 12 ? 'pm' : 'am';
    final displayHour = peakHour % 12 == 0 ? 12 : peakHour % 12;

    return NaviCard(
      // More vertical padding so this card breathes
      padding: const EdgeInsets.fromLTRB(s20, s20, s20, s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Listening hours',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$displayHour$amPm',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: tokens.accent,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'peak hour',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // More space before bars
          const SizedBox(height: s24),
          // Taller bars — 110px instead of 68px
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                final count = heatmapData[hour.toString()] ?? 0;
                final intensity = maxCount > 0 ? count / maxCount : 0.0;
                // Min bar height 8px, max 80px — much more readable range
                final barH = 8.0 + intensity * 72.0;
                final isPeak = hour == peakHour;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : kAnimSlow,
                          height: barH,
                          decoration: BoxDecoration(
                            color: isPeak
                                ? tokens.accent
                                : tokens.accent.withValues(alpha:
                                    0.12 + intensity * 0.60,
                                  ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (hour % 6 == 0)
                          Text(
                            hour == 0
                                ? '12a'
                                : hour == 12
                                ? '12p'
                                : hour < 12
                                ? '${hour}a'
                                : '${hour - 12}p',
                            style: TextStyle(
                              color: isPeak ? tokens.accent : tokens.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          const SizedBox(height: 11),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Genre Radar ───────────────────────────────────────────────────────────────

class GenreRadarChart extends StatelessWidget {
  final List<Map<String, dynamic>> genres;
  const GenreRadarChart({super.key, required this.genres});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    if (genres.isEmpty) return const SizedBox.shrink();

    final top = genres.take(6).toList();
    final maxPct = top.fold(0.0, (a, b) => math.max(a, _double(b['pct'])));
    if (maxPct == 0) return const SizedBox.shrink();

    return NaviCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(s20, s20, s20, 0),
            child: Text(
              'Genre mix',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                gridBorderData: BorderSide(
                  color: tokens.textPrimary.withValues(alpha: 0.07),
                  width: 0.5,
                ),
                tickBorderData: const BorderSide(color: Colors.transparent),
                tickCount: 3,
                titleTextStyle: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                getTitle: (index, angle) => RadarChartTitle(
                  text: top[index]['genre']?.toString() ?? '',
                  angle: angle - 90,
                ),
                dataSets: [
                  RadarDataSet(
                    fillColor: tokens.accent.withValues(alpha: 0.10),
                    borderColor: tokens.accent,
                    borderWidth: 1.5,
                    entryRadius: 2.5,
                    dataEntries: top
                        .map(
                          (g) => RadarEntry(
                            value: _double(g['pct']) / maxPct * 100,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(s20, s8, s20, s20),
            child: Column(
              children: List.generate(top.length, (i) {
                final g = top[i];
                final pct = _double(g['pct']);
                final rel = maxPct > 0 ? pct / maxPct : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          g['genre']?.toString() ?? '',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: s8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: radiusFull,
                          child: LinearProgressIndicator(
                            value: rel,
                            minHeight: 3,
                            backgroundColor: tokens.textPrimary.withValues(alpha:
                              0.06,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              tokens.accent.withValues(alpha: 1.0 - i * 0.13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: s8),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  double _double(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

// ── Listening Line Chart ──────────────────────────────────────────────────────

class ListeningLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<String> labels;
  const ListeningLineChart({
    super.key,
    required this.spots,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    bool isUp = true;
    double pctChange = 0.0;
    if (spots.length >= 2) {
      final last = spots.last.y;
      final prev = spots[spots.length - 2].y;
      if (prev > 0) {
        pctChange = ((last - prev) / prev * 100).abs();
        isUp = last >= prev;
      }
    }

    if (spots.length < 2) {
      return NaviCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Listening over time',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: s16),
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Not enough data',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final trendColor = isUp ? const Color(0xFF1DB954) : const Color(0xFFFF6B6B);

    return NaviCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(s20, s20, s20, s16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Listening over time',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Icon(
                  isUp ? Icons.north_east_rounded : Icons.south_east_rounded,
                  size: 13,
                  color: trendColor,
                ),
                const SizedBox(width: 3),
                Text(
                  '${pctChange.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: tokens.textPrimary.withValues(alpha: 0.04),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (spots.length / 4).ceilToDouble(),
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            labels[idx],
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: tokens.accent,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) => spot.x == spots.last.x,
                      getDotPainter: (spot, _, __, ___) =>
                          _PingingDotPainter(color: tokens.accent),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          tokens.accent.withValues(alpha: 0.12),
                          tokens.accent.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
              duration: kAnimSlow,
              curve: kCurveStandard,
            ),
          ),
        ],
      ),
    );
  }
}

class _PingingDotPainter extends FlDotPainter {
  final Color color;
  _PingingDotPainter({required this.color});

  @override
  Color get mainColor => color;
  @override
  List<Object?> get props => [color];

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    canvas.drawCircle(offsetInCanvas, 3, Paint()..color = color);
    canvas.drawCircle(
      offsetInCanvas,
      6,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  Size getSize(FlSpot spot) => const Size(12, 12);

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;
}

// ── Model Status ──────────────────────────────────────────────────────────────

class ModelStatusCard extends StatelessWidget {
  final ModelStatusResponse status;
  const ModelStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final progress = status.rebuildThreshold > 0
        ? (1.0 - (status.unprocessedEvents / status.rebuildThreshold)).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    final isActive = progress < 1.0 || status.unprocessedEvents > 0;

    return NaviCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI model',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Personalized shuffle engine',
                      style: TextStyle(fontSize: 11, color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: s8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.10),
                  borderRadius: radiusFull,
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isActive ? 'Active' : 'Idle',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: s20),
          IntrinsicHeight(
            child: Row(
              children: [
                _MS(
                  label: 'Songs',
                  value: '${status.songsInLibrary}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'Plays',
                  value: '${status.totalPlaysProcessed}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'Comp.',
                  value: '${status.composersTracked}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'Ctx',
                  value: '${status.contextBuckets}',
                  tokens: tokens,
                ),
              ],
            ),
          ),
          const SizedBox(height: s20),
          Row(
            children: [
              Text(
                'Rebuild progress',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${status.unprocessedEvents} / ${status.rebuildThreshold}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: s8),
          ClipRRect(
            borderRadius: radiusFull,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: tokens.textPrimary.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(
                progress > 0.8 ? Colors.orange : tokens.accent,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: s8),
          Text(
            '${status.modelSizeMb.toStringAsFixed(1)} MB on device',
            style: TextStyle(color: tokens.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _VD extends StatelessWidget {
  final AppThemeTokens tokens;
  const _VD({required this.tokens});
  @override
  Widget build(BuildContext context) => Container(
    width: 0.5,
    margin: const EdgeInsets.symmetric(horizontal: s8),
    color: tokens.textPrimary.withValues(alpha: 0.1),
  );
}

class _MS extends StatelessWidget {
  final String label, value;
  final AppThemeTokens tokens;
  const _MS({required this.label, required this.value, required this.tokens});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: tokens.textPrimary,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

// ── Top Artists ───────────────────────────────────────────────────────────────

class _TopArtistsList extends StatelessWidget {
  final List<Map<String, dynamic>> artists;
  const _TopArtistsList({required this.artists});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    if (artists.isEmpty) return const SizedBox.shrink();

    final maxPlays = artists.fold<int>(0, (max, a) {
      final p = a['play_count'] as int? ?? 0;
      return p > max ? p : max;
    });

    final top = artists.take(5).toList();

    return Column(
      children: top.asMap().entries.map((entry) {
        final i = entry.key;
        final a = entry.value;
        final name = a['artist']?.toString() ?? 'Unknown';
        final plays = a['play_count'] as int? ?? 0;
        final ratio = maxPlays > 0 ? plays / maxPlays : 0.0;
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

        final rankColor = i == 0
            ? const Color(0xFFFFD700)
            : i == 1
            ? const Color(0xFFCCCCCC)
            : i == 2
            ? const Color(0xFFCD7F32)
            : tokens.textMuted.withValues(alpha: 0.5);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: tokens.textPrimary.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: i == 0 ? 20 : 14,
                    fontWeight: FontWeight.w900,
                    color: rankColor,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: s8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: tokens.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: radiusFull,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: ratio),
                        duration: kAnimSlow,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 2,
                          backgroundColor: tokens.textPrimary.withValues(alpha: 0.05),
                          valueColor: AlwaysStoppedAnimation(
                            tokens.accent.withValues(alpha: 0.4 + ratio * 0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: s12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$plays',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'plays',
                    style: TextStyle(color: tokens.textMuted, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Top Tracks ────────────────────────────────────────────────────────────────

class _TopTracksList extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  const _TopTracksList({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    if (tracks.isEmpty) return const SizedBox.shrink();

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final t in tracks) {
      final title = t['title']?.toString() ?? 'Unknown';
      if (!seen.contains(title)) {
        seen.add(title);
        unique.add(t);
      }
      if (unique.length >= 5) break;
    }

    return Column(
      children: unique.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        final title = t['title']?.toString() ?? 'Unknown';
        final artist = t['artist']?.toString() ?? 'Unknown';
        final plays = t['play_count'] as int? ?? 0;

        final hue = (title.hashCode.abs() % 360).toDouble();
        final hsl = HSLColor.fromAHSL(1.0, hue, 0.60, 0.36).toColor();

        final ratioRaw = t['avg_listen_ratio'];
        final ratio = ratioRaw is num ? ratioRaw.toDouble() : 1.0;
        final ratioColor = ratio >= 0.8
            ? const Color(0xFF1DB954)
            : ratio >= 0.5
            ? const Color(0xFFFFD700)
            : const Color(0xFFFF6B6B);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: tokens.textPrimary.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tokens.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: s8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: hsl,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white70,
                  size: 17,
                ),
              ),
              const SizedBox(width: s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: radiusFull,
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 2,
                              backgroundColor: tokens.textPrimary.withValues(alpha:
                                0.05,
                              ),
                              valueColor: AlwaysStoppedAnimation(ratioColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: s8),
                        Text(
                          '${(ratio * 100).toInt()}%',
                          style: TextStyle(
                            color: ratioColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: s12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$plays',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'plays',
                    style: TextStyle(color: tokens.textMuted, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
