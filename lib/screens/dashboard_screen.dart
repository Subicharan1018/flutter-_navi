import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;


import '../core/theme.dart';
import '../providers/library_provider.dart';

import '../widgets/navi_ui.dart';
import '../widgets/contribution_graph.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../features/ai_shuffle/data/models/model_status_response.dart';
import '../features/ai_shuffle/data/models/contribution_graph_response.dart';

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

    // The app shell sets extendBody:true, so this scroll view runs *behind* the
    // 68px mini-player + 56px nav bar. Without this clearance the last card
    // (AI model) sits permanently under the mini player.
    final bottomClearance =
        68.0 + 56.0 + s16 + MediaQuery.viewPaddingOf(context).bottom;

    // "Listening over time" is driven by the contribution graph's real per-day
    // counts (not the 20-row recent_plays sample, which made the line read as a
    // flat zero with a single end spike). Window tracks the selected period.
    final contribDays =
        ref.watch(contributionGraphProvider).asData?.value.days ??
        const <ContributionDay>[];
    final lineWindow = _period == StatsPeriod.weekly
        ? 7
        : _period == StatsPeriod.monthly
            ? 30
            : 90;
    final lineSpots = _spotsFromContribution(contribDays, lineWindow);
    final lineLabels = _dayLabels(lineWindow);

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
                padding: EdgeInsets.fromLTRB(s16, s20, s16, bottomClearance),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 950;
                      if (isWide) {
                        return _buildWideLayout(
                          stats, modelAsync, tokens, lineSpots, lineLabels);
                      } else {
                        return _buildNarrowLayout(
                          stats, modelAsync, tokens, lineSpots, lineLabels);
                      }
                    },
                  ),
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

  Widget _buildWideLayout(
    ListeningStatsResponse stats,
    AsyncValue<ModelStatusResponse> modelAsync,
    AppThemeTokens tokens,
    List<FlSpot> lineSpots,
    List<String> lineLabels,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Metrics on Left (4), Listening over time (Line Chart) on Right (6)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: _MetricsRow(stats: stats, tokens: tokens),
            ),
            const SizedBox(width: s24),
            Expanded(
              flex: 6,
              child: ListeningLineChart(
                spots: lineSpots,
                labels: lineLabels,
              ),
            ),
          ],
        ),
        const SizedBox(height: s24),

        // Row 2: Listening Hours (Heatmap) on Left, Genre Mix (Radar) on Right
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HourlyHeatmap(heatmapData: stats.hourlyHeatmap),
            ),
            const SizedBox(width: s24),
            Expanded(
              child: GenreMixCard(genres: stats.genreBreakdown),
            ),
          ],
        ),
        const SizedBox(height: s24),

        // Row 3: Top Artists side-by-side with Top Tracks
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PremiumCard(
                padding: const EdgeInsets.all(s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(text: 'Top artists', tokens: tokens),
                    const SizedBox(height: s12),
                    _TopArtistsList(artists: stats.topArtists),
                  ],
                ),
              ),
            ),
            const SizedBox(width: s24),
            Expanded(
              child: PremiumCard(
                padding: const EdgeInsets.all(s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(text: 'Top tracks', tokens: tokens),
                    const SizedBox(height: s12),
                    _TopTracksList(tracks: stats.topTracks),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: s24),

        // Row 4: Consistency (Contribution Graph) on Left (65), AI Model Status on Right (35)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              flex: 65,
              child: ContributionGraphCard(),
            ),
            const SizedBox(width: s24),
            Expanded(
              flex: 35,
              child: modelAsync.when(
                data: (m) => ModelStatusCard(status: m),
                loading: () => const NaviSkeleton(height: 140),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        const SizedBox(height: s8),
      ],
    );
  }

  Widget _buildNarrowLayout(
    ListeningStatsResponse stats,
    AsyncValue<ModelStatusResponse> modelAsync,
    AppThemeTokens tokens,
    List<FlSpot> lineSpots,
    List<String> lineLabels,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricsRow(stats: stats, tokens: tokens),
        const SizedBox(height: s16),

        // Group 1 — when you listen (hour of day + genre), tighter internal gap.
        HourlyHeatmap(heatmapData: stats.hourlyHeatmap),
        const SizedBox(height: s12),

        GenreMixCard(genres: stats.genreBreakdown),
        const SizedBox(height: s16),

        // Group 2 — activity over time (year grid + windowed trend).
        const ContributionGraphCard(),
        const SizedBox(height: s12),

        ListeningLineChart(
          spots: lineSpots,
          labels: lineLabels,
        ),
        const SizedBox(height: s16),

        _Label(text: 'Top artists', tokens: tokens),
        const SizedBox(height: s8),
        _TopArtistsList(artists: stats.topArtists),
        const SizedBox(height: s16),

        _Label(text: 'Top tracks', tokens: tokens),
        const SizedBox(height: s8),
        _TopTracksList(tracks: stats.topTracks),
        const SizedBox(height: s16),

        modelAsync.when(
          data: (m) => ModelStatusCard(status: m),
          loading: () => const NaviSkeleton(height: 140),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: s8),
      ],
    );
  }

  /// One spot per day across the trailing [window] days, sourced from the
  /// contribution graph's real per-day play counts.
  List<FlSpot> _spotsFromContribution(List<ContributionDay> days, int window) {
    final byDate = {for (final d in days) d.date: d.count};
    final now = DateTime.now();
    return List.generate(window, (i) {
      final d = now.subtract(Duration(days: window - 1 - i));
      return FlSpot(i.toDouble(), (byDate[_isoDate(d)] ?? 0).toDouble());
    });
  }

  List<String> _dayLabels(int window) {
    final now = DateTime.now();
    return List.generate(window, (i) {
      final d = now.subtract(Duration(days: window - 1 - i));
      return '${_two(d.month)}-${_two(d.day)}';
    });
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _two(int n) => n.toString().padLeft(2, '0');
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
          'Listening insights',
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
    final mode = tokens.mode;
    
    TextStyle titleStyle;
    if (mode == AppThemeMode.zen) {
      titleStyle = tokens.textStyle(28, FontWeight.w400, tokens.textPrimary).copyWith(
        letterSpacing: -0.5,
        height: 1.1,
      );
    } else if (mode == AppThemeMode.analog) {
      titleStyle = tokens.textStyle(28, FontWeight.w800, tokens.textPrimary).copyWith(
        letterSpacing: -0.5,
        height: 1.1,
      );
    } else {
      titleStyle = TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: tokens.textPrimary,
        letterSpacing: -0.8,
        height: 1.1,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listening insights',
          style: titleStyle,
        ),
        const SizedBox(height: 3),
        Text(
          'Your library footprint and sonic patterns',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: tokens.textMuted,
            letterSpacing: 0.1,
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
    final mode = tokens.mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    BorderRadius trackRadius = BorderRadius.circular(20);
    BorderRadius capsuleRadius = BorderRadius.circular(18);
    Color trackColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);
    Color capsuleColor = tokens.accent;
    List<BoxShadow> capsuleShadow = [
      BoxShadow(
        color: tokens.accent.withValues(alpha: 0.25),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
    BoxBorder? trackBorder = Border.all(
      color: tokens.textPrimary.withValues(alpha: 0.05),
      width: 0.5,
    );

    switch (mode) {
      case AppThemeMode.spotify:
        trackColor = tokens.bgElevated;
        capsuleColor = tokens.accent;
        capsuleShadow = [];
        trackBorder = Border.all(color: tokens.outline, width: 1);
        break;
      case AppThemeMode.aura:
        trackColor = tokens.bgElevated;
        capsuleColor = tokens.accent;
        capsuleShadow = [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
        break;
      case AppThemeMode.frost:
        trackColor = Colors.white.withValues(alpha: 0.06);
        capsuleColor = Colors.white.withValues(alpha: 0.2);
        trackBorder = Border.all(color: tokens.glassBorder, width: 0.5);
        capsuleShadow = [];
        break;
      case AppThemeMode.neumorphic:
        trackColor = tokens.bgOverlay;
        capsuleColor = tokens.bgBase;
        capsuleShadow = [
          BoxShadow(
            color: tokens.neuDark.withValues(alpha: 0.6),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: tokens.neuLight,
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
        ];
        trackRadius = BorderRadius.circular(12);
        capsuleRadius = BorderRadius.circular(10);
        trackBorder = null;
        break;
      case AppThemeMode.analog:
        trackColor = tokens.bgElevated.withValues(alpha: 0.5);
        capsuleColor = tokens.accent;
        capsuleShadow = [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ];
        trackBorder = Border.all(color: tokens.outline.withValues(alpha: 0.5), width: 1);
        break;
      case AppThemeMode.zen:
        trackColor = tokens.bgSurface;
        capsuleColor = tokens.textPrimary;
        capsuleShadow = [];
        trackRadius = BorderRadius.zero;
        capsuleRadius = BorderRadius.zero;
        trackBorder = Border.all(color: tokens.textPrimary, width: 1);
        break;
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: trackRadius,
        border: trackBorder,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final tabWidth = width / StatsPeriod.values.length;
          final selectedIndex = StatsPeriod.values.indexOf(selected);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuart,
                left: selectedIndex * tabWidth,
                width: tabWidth,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: capsuleColor,
                    borderRadius: capsuleRadius,
                    boxShadow: capsuleShadow,
                  ),
                ),
              ),
              Row(
                children: StatsPeriod.values.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final p = entry.value;
                  final isSelected = idx == selectedIndex;

                  Color textColor;
                  if (isSelected) {
                    textColor = mode == AppThemeMode.zen 
                        ? tokens.bgBase 
                        : (mode == AppThemeMode.frost ? tokens.textPrimary : tokens.bgBase);
                  } else {
                    textColor = tokens.textSecondary;
                  }

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(p),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            letterSpacing: 0.1,
                          ),
                          child: Text(p.label),
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
    Color skipColor = tokens.positive;
    if (skipRate > 20) {
      skipColor = tokens.danger;
    } else if (skipRate >= 10) {
      skipColor = tokens.warning;
    }

    final cards = [
      _MetricCard(
        label: 'Plays',
        value: _fmtValue(stats.totalPlays),
        rawNumber: stats.totalPlays,
        subtitle: 'tracks streamed',
        icon: Icons.play_arrow_rounded,
        accent: tokens.accent,
        tokens: tokens,
      ),
      _MetricCard(
        label: 'Minutes',
        value: _fmtValue(stats.totalMinutes),
        rawNumber: stats.totalMinutes,
        subtitle: 'total airtime',
        icon: Icons.headset_rounded,
        accent: tokens.accent,
        tokens: tokens,
      ),
      _MetricCard(
        label: 'Skip rate',
        value: '$skipRate%',
        subtitle: 'tracks skipped',
        icon: Icons.skip_next_rounded,
        accent: skipColor,
        tokens: tokens,
      ),
      _MetricCard(
        label: 'Streak',
        value: stats.streakDays > 3 ? '${stats.streakDays}d 🔥' : '${stats.streakDays}d',
        subtitle: 'consecutive days',
        icon: Icons.local_fire_department_rounded,
        accent: stats.streakDays > 3 ? tokens.warning : tokens.textPrimary,
        tokens: tokens,
      ),
    ];

    // Content-sized rows (IntrinsicHeight + stretch) instead of a fixed
    // childAspectRatio grid: cards grow to fit their content, so nothing can
    // overflow, and paired cards stay equal height.
    Widget row(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: s12),
              Expanded(child: b),
            ],
          ),
        );

    return Column(
      children: [
        row(cards[0], cards[1]),
        const SizedBox(height: s12),
        row(cards[2], cards[3]),
      ],
    );
  }

  String _fmtValue(int v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return v.toString();
  }
}

class _MetricCard extends StatefulWidget {
  final String label;
  final String value;
  final int? rawNumber;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final AppThemeTokens tokens;

  const _MetricCard({
    required this.label,
    required this.value,
    this.rawNumber,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.tokens,
  });

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final mode = tokens.mode;

    final numberStyle = mode == AppThemeMode.zen
        ? tokens.textStyle(32, FontWeight.w400, tokens.textPrimary).copyWith(
              letterSpacing: -1.0,
              height: 1.0,
            )
        : (mode == AppThemeMode.analog
            ? tokens.textStyle(30, FontWeight.w800, tokens.textPrimary).copyWith(
                  letterSpacing: -0.5,
                  height: 1.0,
                )
            : TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: tokens.textPrimary,
                letterSpacing: -1.0,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ));

    final numberWidget = widget.rawNumber != null
        ? TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: widget.rawNumber!),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => Text(_fmt(val), style: numberStyle, maxLines: 1),
          )
        : Text(widget.value, style: numberStyle, maxLines: 1);

    Widget content = PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -14,
            child: Icon(
              widget.icon,
              size: 64,
              color: widget.accent.withValues(alpha: 0.05),
            ),
          ),
          // mainAxisSize.min → the card grows to fit content (can't overflow);
          // FittedBox keeps even a wide value ("12.8k") inside its width.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: numberWidget,
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {},
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _isPressed ? 0.96 : 1.0,
          curve: Curves.easeOut,
          child: content,
        ),
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

// ── Hourly Heatmap ────────────────────────────────────────────────────────────

class HourlyHeatmap extends StatefulWidget {
  final Map<String, int> heatmapData;
  const HourlyHeatmap({super.key, required this.heatmapData});

  @override
  State<HourlyHeatmap> createState() => _HourlyHeatmapState();
}

class _HourlyHeatmapState extends State<HourlyHeatmap> {
  int? _selectedHour;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final mode = tokens.mode;
    final maxCount = widget.heatmapData.values.fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    int peakHour = 0;
    widget.heatmapData.forEach((hour, count) {
      if (count == maxCount) peakHour = int.parse(hour);
    });

    final displayHour = _selectedHour ?? peakHour;
    final amPm = displayHour >= 12 ? 'pm' : 'am';
    final hr12 = displayHour % 12 == 0 ? 12 : displayHour % 12;
    
    final displayCount = widget.heatmapData[displayHour.toString()] ?? 0;
    final labelText = _selectedHour != null ? 'plays' : 'peak hour';

    return PremiumCard(
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedHour != null) ...[
                        Text(
                          '$displayCount ',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: tokens.accent,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          'at ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                      Text(
                        '$hr12$amPm',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: _selectedHour != null ? tokens.textPrimary : tokens.accent,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    labelText,
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
          const SizedBox(height: s24),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                final count = widget.heatmapData[hour.toString()] ?? 0;
                final intensity = maxCount > 0 ? count / maxCount : 0.0;
                final barH = 8.0 + intensity * 72.0;
                final isPeak = hour == peakHour;
                final isSelected = hour == _selectedHour;

                BorderRadius barRadius = const BorderRadius.vertical(top: Radius.circular(3));
                BoxDecoration? decoration;

                if (mode == AppThemeMode.zen) {
                  barRadius = BorderRadius.zero;
                  decoration = BoxDecoration(
                    color: isSelected 
                        ? tokens.textPrimary 
                        : tokens.textPrimary.withValues(alpha: 0.12 + intensity * 0.6),
                    border: Border.all(
                      color: tokens.textPrimary,
                      width: isSelected ? 1.0 : 0.5,
                    ),
                  );
                } else if (mode == AppThemeMode.aura) {
                  barRadius = BorderRadius.circular(4);
                  decoration = BoxDecoration(
                    borderRadius: barRadius,
                    gradient: LinearGradient(
                      colors: [
                        tokens.accent.withValues(alpha: 0.15),
                        tokens.accent.withValues(
                          alpha: isSelected ? 1.0 : (0.2 + intensity * 0.7),
                        ),
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    boxShadow: isSelected || isPeak
                        ? [
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.3),
                              blurRadius: 4,
                              spreadRadius: 0.5,
                            )
                          ]
                        : null,
                  );
                } else if (mode == AppThemeMode.analog) {
                  barRadius = BorderRadius.circular(6);
                  decoration = BoxDecoration(
                    color: isSelected
                        ? tokens.accent
                        : tokens.accent.withValues(alpha: 0.18 + intensity * 0.65),
                    borderRadius: barRadius,
                    border: Border.all(
                      color: tokens.outline.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  );
                } else {
                  decoration = BoxDecoration(
                    color: isSelected
                        ? tokens.accent
                        : (isPeak
                            ? tokens.accent
                            : tokens.accent.withValues(alpha: 0.12 + intensity * 0.60)),
                    borderRadius: barRadius,
                  );
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.2),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_selectedHour == hour) {
                            _selectedHour = null;
                          } else {
                            _selectedHour = hour;
                          }
                        });
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: MediaQuery.of(context).disableAnimations
                                ? Duration.zero
                                : kAnimNormal,
                            height: barH,
                            decoration: decoration,
                          ),
                          const SizedBox(height: 6),
                          if (hour % 6 == 0)
                            // The bar slot is only ~13px wide, so a 3-char label
                            // like "12p" wraps to two lines. OverflowBox lets the
                            // centred label render on one line, spilling into the
                            // unlabelled neighbouring slots.
                            SizedBox(
                              height: 11,
                              child: OverflowBox(
                                maxWidth: 40,
                                child: Text(
                                  hour == 0
                                      ? '12a'
                                      : hour == 12
                                          ? '12p'
                                          : hour < 12
                                              ? '${hour}a'
                                              : '${hour - 12}p',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: isSelected
                                        ? tokens.accent
                                        : (isPeak ? tokens.accent : tokens.textMuted),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 11),
                        ],
                      ),
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

class GenreMixCard extends StatelessWidget {
  final List<Map<String, dynamic>> genres;
  const GenreMixCard({super.key, required this.genres});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    if (genres.isEmpty) return const SizedBox.shrink();

    final top = genres.take(6).toList();
    final maxPct = top.fold(0.0, (a, b) => math.max(a, _double(b['pct'])));
    if (maxPct == 0) return const SizedBox.shrink();

    return PremiumCard(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(s20, s16, s20, s20),
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
    final mode = tokens.mode;

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
      return PremiumCard(
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

    final trendColor = isUp ? tokens.positive : tokens.danger;

    return PremiumCard(
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
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => tokens.bgSurfaceOpaque,
                    tooltipBorder: BorderSide(
                      color: tokens.textPrimary.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                    tooltipBorderRadius: mode == AppThemeMode.zen 
                        ? BorderRadius.zero 
                        : BorderRadius.circular(8.0),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((touchedSpot) {
                        final idx = touchedSpot.x.toInt();
                        if (idx < 0 || idx >= labels.length) return null;
                        final dateStr = labels[idx];
                        final val = touchedSpot.y.toInt();
                        
                        return LineTooltipItem(
                          '$dateStr\n',
                          TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: '$val ${val == 1 ? 'play' : 'plays'}',
                              style: TextStyle(
                                color: mode == AppThemeMode.zen ? tokens.textPrimary : tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
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
    final statusColor = isActive ? tokens.accent : tokens.textMuted;

    return PremiumCard(
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
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: radiusFull,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
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
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isActive ? 'Active' : 'Idle',
                      style: TextStyle(
                        color: statusColor,
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
                  fontFeatures: const [FontFeature.tabularFigures()],
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
                progress > 0.8 ? tokens.warning : tokens.accent,
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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

        // Derive high-end visual gradient colors for artist avatar from name hash
        final hue = (name.hashCode.abs() % 360).toDouble();
        final color1 = HSLColor.fromAHSL(1.0, hue, 0.65, 0.40).toColor();
        final color2 = HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.70, 0.25).toColor();

        // Podium ramp: gold (themed warm signal) for #1, then neutral text
        // tones. Avoids silver/bronze literals that vanish on the light themes
        // and bleed colour into the monochrome Zen theme.
        final rankColor = i == 0
            ? tokens.gold
            : i == 1
            ? tokens.textSecondary
            : i == 2
            ? tokens.textMuted
            : tokens.textMuted.withValues(alpha: 0.5);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: tokens.textPrimary.withValues(alpha: 0.04),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Stylized Rank Number
              SizedBox(
                width: 28,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: i == 0 ? 22 : 15,
                    fontWeight: FontWeight.w900,
                    color: rankColor,
                    letterSpacing: -0.5,
                    fontStyle: FontStyle.italic,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: s8),
              // Circular Artist Gradient Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color1, color2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: tokens.textPrimary.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color1.withValues(alpha: 0.15),
                      blurRadius: 6,
                      spreadRadius: 1,
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: s12),
              // Artist Name & Track count bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
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
                          minHeight: 3,
                          backgroundColor: tokens.textPrimary.withValues(alpha: 0.04),
                          valueColor: AlwaysStoppedAnimation(
                            tokens.accent.withValues(alpha: 0.3 + ratio * 0.7),
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

class _TopTracksList extends ConsumerWidget {
  final List<Map<String, dynamic>> tracks;
  const _TopTracksList({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final color1 = HSLColor.fromAHSL(1.0, hue, 0.60, 0.36).toColor();
        final color2 = HSLColor.fromAHSL(1.0, (hue + 45) % 360, 0.65, 0.20).toColor();

        final ratioRaw = t['avg_listen_ratio'];
        final ratio = ratioRaw is num ? ratioRaw.toDouble() : 1.0;
        final ratioColor = ratio >= 0.8
            ? tokens.positive
            : ratio >= 0.5
            ? tokens.warning
            : tokens.danger;

        final coverUrlAsync = ref.watch(songCoverUrlProvider('$title|$artist'));

        // Podium ramp: gold (themed warm signal) for #1, then neutral text
        // tones. Avoids silver/bronze literals that vanish on the light themes
        // and bleed colour into the monochrome Zen theme.
        final rankColor = i == 0
            ? tokens.gold
            : i == 1
            ? tokens.textSecondary
            : i == 2
            ? tokens.textMuted
            : tokens.textMuted.withValues(alpha: 0.5);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: tokens.textPrimary.withValues(alpha: 0.04),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Stylized Rank Number
              SizedBox(
                width: 28,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: i == 0 ? 22 : 15,
                    fontWeight: FontWeight.w900,
                    color: rankColor,
                    letterSpacing: -0.5,
                    fontStyle: FontStyle.italic,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: s8),
              // Rounded Square Album Art with Double Rim Highlight (Double-Bezel concept)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: tokens.textPrimary.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: coverUrlAsync.when(
                    data: (url) => url != null && url.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            memCacheWidth: 80,
                            memCacheHeight: 80,
                            placeholder: (_, __) => _placeholder(color1, color2),
                            errorWidget: (_, __, ___) => _placeholder(color1, color2),
                          )
                        : _placeholder(color1, color2),
                    loading: () => _placeholder(color1, color2),
                    error: (_, __) => _placeholder(color1, color2),
                  ),
                ),
              ),
              const SizedBox(width: s12),
              // Song Info and listen ratio bar
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
                              minHeight: 3,
                              backgroundColor: tokens.textPrimary.withValues(alpha: 0.04),
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

  Widget _placeholder(Color c1, Color c2) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white70,
        size: 16,
      ),
    );
  }
}
