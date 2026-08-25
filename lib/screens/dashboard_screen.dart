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
                        return _buildWideLayout(stats, modelAsync, tokens,
                            lineSpots, lineLabels, contribDays);
                      } else {
                        return _buildNarrowLayout(stats, modelAsync, tokens,
                            lineSpots, lineLabels, contribDays);
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
    List<ContributionDay> contribDays,
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
              child: _SummaryBand(
                stats: stats,
                tokens: tokens,
                contribDays: contribDays,
              ),
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
                    _SectionHeader(title: 'Top artists', tokens: tokens),
                    const SizedBox(height: s8),
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
                    _SectionHeader(title: 'Top tracks', tokens: tokens),
                    const SizedBox(height: s8),
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
                error: (error, stackTrace) => const SizedBox.shrink(),
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
    List<ContributionDay> contribDays,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBand(
          stats: stats,
          tokens: tokens,
          contribDays: contribDays,
        ),
        const SizedBox(height: s24),

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

        PremiumCard(
          padding: const EdgeInsets.all(s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Top artists', tokens: tokens),
              const SizedBox(height: s8),
              _TopArtistsList(artists: stats.topArtists),
            ],
          ),
        ),
        const SizedBox(height: s12),

        PremiumCard(
          padding: const EdgeInsets.all(s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Top tracks', tokens: tokens),
              const SizedBox(height: s8),
              _TopTracksList(tracks: stats.topTracks),
            ],
          ),
        ),
        const SizedBox(height: s16),

        modelAsync.when(
          data: (m) => ModelStatusCard(status: m),
          loading: () => const NaviSkeleton(height: 140),
          error: (error, stackTrace) => const SizedBox.shrink(),
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

/// The one section-header vocabulary on this screen. [trailing] carries the
/// section's own headline readout (peak hour, trend, model state) so each card
/// leads with its answer instead of repeating a title-only bar.
class _SectionHeader extends StatelessWidget {
  final String title;
  final AppThemeTokens tokens;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.tokens,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final style = tokens.mode == AppThemeMode.zen
        ? tokens
            .textStyle(15, FontWeight.w500, tokens.textPrimary)
            .copyWith(letterSpacing: -0.2)
        : TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
            letterSpacing: -0.3,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: style, maxLines: 1)),
        if (trailing != null) ...[
          const SizedBox(width: s12),
          trailing!,
        ],
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

// ── Summary band ──────────────────────────────────────────────────────────────

/// Type rule for every large figure on this screen, so the dashboard has one
/// numeric voice instead of each card inventing its own.
TextStyle _figureStyle(AppThemeTokens tokens, double size) {
  switch (tokens.mode) {
    case AppThemeMode.zen:
      return tokens
          .textStyle(size, FontWeight.w400, tokens.textPrimary)
          .copyWith(letterSpacing: -size * 0.03, height: 1.0);
    case AppThemeMode.analog:
      return tokens
          .textStyle(size, FontWeight.w800, tokens.textPrimary)
          .copyWith(letterSpacing: -size * 0.02, height: 1.0);
    default:
      return TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: tokens.textPrimary,
        letterSpacing: -size * 0.03,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
  }
}

/// Caption rule paired with [_figureStyle] — what the figure counts.
TextStyle _captionStyle(AppThemeTokens tokens) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: tokens.textSecondary,
      letterSpacing: 0.1,
    );

/// The four period totals, read as page-level facts rather than four cards.
///
/// Deliberately *not* a grid of equal tiles: the two volume figures are the
/// headline and sit directly on the page, while skip rate and streak are drawn
/// as the shapes they actually are — a proportion and a run of days. The cards
/// below this band are analyses; this band is the summary, and the difference
/// in treatment is what gives the screen a top.
class _SummaryBand extends StatelessWidget {
  final ListeningStatsResponse stats;
  final AppThemeTokens tokens;
  final List<ContributionDay> contribDays;

  const _SummaryBand({
    required this.stats,
    required this.tokens,
    required this.contribDays,
  });

  @override
  Widget build(BuildContext context) {
    final skipPct = (stats.skipRate * 100).round().clamp(0, 100);
    final Color skipColor = skipPct > 20
        ? tokens.danger
        : skipPct >= 10
            ? tokens.warning
            : tokens.positive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Figure(
                  tokens: tokens,
                  target: stats.totalPlays,
                  format: _compact,
                  caption: 'plays',
                ),
              ),
              _Rule(tokens: tokens, vertical: true),
              Expanded(
                child: _Figure(
                  tokens: tokens,
                  target: stats.totalMinutes,
                  format: _duration,
                  caption: 'listened',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: s20),
        _Rule(tokens: tokens),
        const SizedBox(height: s16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SkipReadout(
                  tokens: tokens,
                  pct: skipPct,
                  color: skipColor,
                ),
              ),
              const SizedBox(width: s20),
              Expanded(
                child: _StreakReadout(
                  tokens: tokens,
                  days: stats.streakDays,
                  contribDays: contribDays,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _compact(int v) {
    if (v < 1000) return '$v';
    final k = v / 1000;
    return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
  }

  /// Minutes are only meaningful as minutes up to about an hour; past that a
  /// reader wants hours. "4.3k" tells you nothing about how long you listened.
  static String _duration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h >= 100) return '${h}h';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// A counting figure with its caption underneath.
class _Figure extends StatelessWidget {
  final AppThemeTokens tokens;
  final int target;
  final String Function(int) format;
  final String caption;

  const _Figure({
    required this.tokens,
    required this.target,
    required this.format,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final style = _figureStyle(tokens, 38);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: reduceMotion
              ? Text(format(target), style: style, maxLines: 1)
              : TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: target),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) =>
                      Text(format(v), style: style, maxLines: 1),
                ),
        ),
        const SizedBox(height: 6),
        Text(caption, style: _captionStyle(tokens)),
      ],
    );
  }
}

/// Skip rate drawn as the proportion it is: one track split between the part
/// you played through and the part you skipped.
class _SkipReadout extends StatelessWidget {
  final AppThemeTokens tokens;
  final int pct;
  final Color color;

  const _SkipReadout({
    required this.tokens,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final kept = 100 - pct;
    final isZen = tokens.mode == AppThemeMode.zen;
    final radius = isZen ? BorderRadius.zero : radiusFull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Skip rate', style: _captionStyle(tokens)),
        const SizedBox(height: s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$pct', style: _figureStyle(tokens, 20).copyWith(color: color)),
            Text(
              '%',
              style: _figureStyle(tokens, 13).copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: s8),
        ClipRRect(
          borderRadius: radius,
          child: Row(
            children: [
              Expanded(
                flex: kept.clamp(0, 100),
                child: Container(
                  height: 4,
                  color: tokens.textPrimary.withValues(alpha: 0.16),
                ),
              ),
              if (pct > 0) ...[
                const SizedBox(width: 2),
                Expanded(
                  flex: pct,
                  child: Container(height: 4, color: color),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$kept% played through',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// Streak drawn as the run it is: the trailing fortnight, one tick per day,
/// filled on days you listened. The number alone can't show you that the run
/// is about to break.
class _StreakReadout extends StatelessWidget {
  final AppThemeTokens tokens;
  final int days;
  final List<ContributionDay> contribDays;

  const _StreakReadout({
    required this.tokens,
    required this.days,
    required this.contribDays,
  });

  static const int _window = 14;

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final d in contribDays) d.date: d.count};
    final now = DateTime.now();
    final played = List<bool>.generate(_window, (i) {
      final d = now.subtract(Duration(days: _window - 1 - i));
      final key = '${d.year}-${_two(d.month)}-${_two(d.day)}';
      return (byDate[key] ?? 0) > 0;
    });

    final isZen = tokens.mode == AppThemeMode.zen;
    final live = days > 0 ? tokens.accent : tokens.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Streak', style: _captionStyle(tokens)),
        const SizedBox(height: s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$days', style: _figureStyle(tokens, 20)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                days == 1 ? 'day' : 'days',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: s8),
        SizedBox(
          height: 4,
          child: Row(
            children: [
              for (var i = 0; i < _window; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: played[i]
                          ? live
                          : tokens.textPrimary.withValues(alpha: 0.10),
                      borderRadius: isZen ? null : radiusFull,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'last 14 days',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: tokens.textMuted),
        ),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Hairline divider — the one separator vocabulary for this screen.
class _Rule extends StatelessWidget {
  final AppThemeTokens tokens;
  final bool vertical;
  const _Rule({required this.tokens, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final color = tokens.textPrimary.withValues(alpha: 0.10);
    return vertical
        ? Container(
            width: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: s20),
            color: color,
          )
        : Container(height: 0.5, color: color);
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
          _SectionHeader(
            title: 'Listening hours',
            tokens: tokens,
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (_selectedHour != null) ...[
                      Text(
                        '$displayCount',
                        style: _figureStyle(tokens, 22)
                            .copyWith(color: tokens.accent),
                      ),
                      Text(
                        ' at ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                    Text(
                      '$hr12$amPm',
                      style: _figureStyle(tokens, 22).copyWith(
                        color: _selectedHour != null
                            ? tokens.textPrimary
                            : tokens.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(labelText, style: _captionStyle(tokens)),
              ],
            ),
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
            child: _SectionHeader(title: 'Genre mix', tokens: tokens),
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
            _SectionHeader(title: 'Listening over time', tokens: tokens),
            const SizedBox(height: s16),
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Two days of listening will draw this line.',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
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
            child: _SectionHeader(
              title: 'Listening over time',
              tokens: tokens,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUp ? Icons.north_east_rounded : Icons.south_east_rounded,
                    size: 13,
                    color: trendColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${pctChange.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: trendColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
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
                      getDotPainter: (spot, percent, barData, index) =>
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
          _SectionHeader(
            title: 'Shuffle model',
            tokens: tokens,
            trailing: Row(
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
                  isActive ? 'Learning' : 'Up to date',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Trained on your library to order shuffles',
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
          const SizedBox(height: s20),
          IntrinsicHeight(
            child: Row(
              children: [
                _MS(
                  label: 'songs',
                  value: '${status.songsInLibrary}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'plays learned',
                  value: '${status.totalPlaysProcessed}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'composers',
                  value: '${status.composersTracked}',
                  tokens: tokens,
                ),
                _VD(tokens: tokens),
                _MS(
                  label: 'contexts',
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
          child: Text(value, maxLines: 1, style: _figureStyle(tokens, 17)),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

// ── Ranked lists ──────────────────────────────────────────────────────────────

/// Shared chassis for the two ranked lists. They rank the same library by the
/// same play counts and differ only in what sits in the artwork slot and what
/// the secondary line says, so they share one row rather than two copies that
/// drift apart.
class _RankedRow extends StatelessWidget {
  final AppThemeTokens tokens;
  final int index;
  final Widget artwork;
  final String title;
  final String? subtitle;
  final int plays;
  final Widget? meter;
  final bool isLast;

  const _RankedRow({
    required this.tokens,
    required this.index,
    required this.artwork,
    required this.title,
    this.subtitle,
    required this.plays,
    this.meter,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    // The leader is marked once, by weight and by the theme's warm signal.
    // Ranks 2+ are ordinary — a full metal ramp would give four rows four
    // different colours and no hierarchy at all.
    final isLeader = index == 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tokens.textPrimary.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
                color: isLeader ? tokens.gold : tokens.textMuted,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: s12),
          artwork,
          const SizedBox(width: s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: isLeader ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13.5,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (meter != null) ...[
                  const SizedBox(height: 6),
                  meter!,
                ],
              ],
            ),
          ),
          const SizedBox(width: s12),
          Text(
            '$plays',
            style: TextStyle(
              color: isLeader ? tokens.textPrimary : tokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Square artwork slot. Shows the real cover when the library has one; when it
/// doesn't, it stays a quiet themed surface carrying the initial. It never
/// synthesises a colour from a hash — a fabricated gradient reads as content
/// the app doesn't actually have.
class _Artwork extends StatelessWidget {
  final AppThemeTokens tokens;
  final AsyncValue<String?> urlAsync;
  final String label;
  final double size;
  final bool circular;

  const _Artwork({
    required this.tokens,
    required this.urlAsync,
    required this.label,
    this.size = 38,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final isZen = tokens.mode == AppThemeMode.zen;
    final radius = circular
        ? BorderRadius.circular(size)
        : BorderRadius.circular(isZen ? 0 : 6);

    final url = urlAsync.asData?.value;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: radius,
        border: Border.all(
          color: tokens.textPrimary.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              memCacheHeight: 96,
              fadeInDuration: kAnimFast,
              placeholder: (_, _) => _monogram(),
              errorWidget: (_, _, _) => _monogram(),
            )
          : _monogram(),
    );
  }

  Widget _monogram() => Center(
        child: Text(
          label.isNotEmpty ? label.characters.first.toUpperCase() : '·',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Hairline meter used inside a ranked row.
class _RowMeter extends StatelessWidget {
  final AppThemeTokens tokens;
  final double value;
  final Color color;
  final String? trailing;

  const _RowMeter({
    required this.tokens,
    required this.value,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: tokens.mode == AppThemeMode.zen ? BorderRadius.zero : radiusFull,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: MediaQuery.of(context).disableAnimations ? Duration.zero : kAnimSlow,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 3,
          backgroundColor: tokens.textPrimary.withValues(alpha: 0.06),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );

    if (trailing == null) return bar;
    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: s8),
        Text(
          trailing!,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TopArtistsList extends ConsumerWidget {
  final List<Map<String, dynamic>> artists;
  const _TopArtistsList({required this.artists});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    if (artists.isEmpty) {
      return _EmptyRail(
        tokens: tokens,
        message: 'No artist has enough plays in this period yet.',
      );
    }

    final top = artists.take(5).toList();
    final maxPlays = top.fold<int>(
      0,
      (m, a) => math.max(m, (a['play_count'] as int?) ?? 0),
    );

    return Column(
      children: List.generate(top.length, (i) {
        final a = top[i];
        final name = a['artist']?.toString() ?? 'Unknown';
        final plays = (a['play_count'] as int?) ?? 0;
        final ratio = maxPlays > 0 ? plays / maxPlays : 0.0;

        return _RankedRow(
          tokens: tokens,
          index: i,
          isLast: i == top.length - 1,
          artwork: _Artwork(
            tokens: tokens,
            urlAsync: ref.watch(artistCoverUrlProvider(name)),
            label: name,
            size: 36,
            circular: tokens.mode != AppThemeMode.zen,
          ),
          title: name,
          plays: plays,
          meter: _RowMeter(
            tokens: tokens,
            value: ratio,
            color: tokens.accent.withValues(alpha: 0.35 + ratio * 0.65),
          ),
        );
      }),
    );
  }
}

class _TopTracksList extends ConsumerWidget {
  final List<Map<String, dynamic>> tracks;
  const _TopTracksList({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    if (tracks.isEmpty) {
      return _EmptyRail(
        tokens: tokens,
        message: 'No track has enough plays in this period yet.',
      );
    }

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final t in tracks) {
      final title = t['title']?.toString() ?? 'Unknown';
      if (seen.add(title)) unique.add(t);
      if (unique.length >= 5) break;
    }

    return Column(
      children: List.generate(unique.length, (i) {
        final t = unique[i];
        final title = t['title']?.toString() ?? 'Unknown';
        final artist = t['artist']?.toString() ?? 'Unknown';
        final plays = (t['play_count'] as int?) ?? 0;

        final ratioRaw = t['avg_listen_ratio'];
        final ratio = ratioRaw is num ? ratioRaw.toDouble().clamp(0.0, 1.0) : 1.0;
        final ratioColor = ratio >= 0.8
            ? tokens.positive
            : ratio >= 0.5
                ? tokens.warning
                : tokens.danger;

        return _RankedRow(
          tokens: tokens,
          index: i,
          isLast: i == unique.length - 1,
          artwork: _Artwork(
            tokens: tokens,
            urlAsync: ref.watch(songCoverUrlProvider('$title|$artist')),
            label: title,
          ),
          title: title,
          subtitle: artist,
          plays: plays,
          meter: _RowMeter(
            tokens: tokens,
            value: ratio,
            color: ratioColor,
            trailing: '${(ratio * 100).round()}% heard',
          ),
        );
      }),
    );
  }
}

/// Empty state that says what would fill the list, not "no data".
class _EmptyRail extends StatelessWidget {
  final AppThemeTokens tokens;
  final String message;
  const _EmptyRail({required this.tokens, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: s16),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: tokens.textSecondary, height: 1.4),
      ),
    );
  }
}
