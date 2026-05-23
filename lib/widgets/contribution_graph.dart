import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../features/ai_shuffle/data/models/contribution_graph_response.dart';
import 'navi_ui.dart';

class ContributionGraphCard extends ConsumerStatefulWidget {
  const ContributionGraphCard({super.key});

  @override
  ConsumerState<ContributionGraphCard> createState() =>
      _ContributionGraphCardState();
}

class _ContributionGraphCardState extends ConsumerState<ContributionGraphCard>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollCtrl;
  late final AnimationController _animCtrl;
  bool _hasScrolled = false;
  int _scrollRetries = 0;

  // Tooltip state
  String? _tooltipText;
  Offset _tooltipOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (_hasScrolled || !_scrollCtrl.hasClients) return;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    if (maxScroll > 0) {
      _hasScrolled = true;
      _scrollCtrl.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (_scrollRetries < 3) {
        _scrollRetries++;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final asyncData = ref.watch(contributionGraphProvider);

    return NaviCard(
      // More breathing room top/bottom
      padding: const EdgeInsets.fromLTRB(s20, s24, s20, s20),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              asyncData.maybeWhen(
                data: (data) {
                  final total = data.days.fold(
                    0,
                    (sum, day) => sum + day.count,
                  );
                  final dateRange =
                      '${data.days.firstOrNull?.date ?? ''} – ${data.days.lastOrNull?.date ?? ''}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Big number up front, label beside it
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _formatNumber(total),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: tokens.textPrimary,
                              letterSpacing: -1.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'plays',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Date range as small subtitle — no caps, no label noise
                      Text(
                        dateRange,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: tokens.accent,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  );
                },
                orElse: () => Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: s20),

              // ── Graph ────────────────────────────────────────────────────
              asyncData.when(
                data: (data) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToEnd(),
                  );
                  return _buildGraph(context, tokens, data.days);
                },
                loading: () => const NaviSkeleton(height: 120),
                error: (e, stack) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      'Error: $e',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: s16),
              _buildLegend(tokens),
            ],
          ),

          // Floating tooltip
          if (_tooltipText != null)
            Positioned(
              left: _tooltipOffset.dx.clamp(0, double.infinity),
              top: _tooltipOffset.dy,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.textPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _tooltipText!,
                    style: TextStyle(
                      color: tokens.bgBase,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return n.toString();
  }

  Widget _buildGraph(
    BuildContext context,
    AppThemeTokens tokens,
    List<ContributionDay> apiDays,
  ) {
    final now = DateTime.now();
    DateTime endDate = DateTime(now.year, now.month, now.day);

    // If the device clock is wrong, but the API has recent data, use the API's date as the end date!
    if (apiDays.isNotEmpty) {
      final lastDateStr = apiDays.last.date;
      final parts = lastDateStr.split('-');
      if (parts.length == 3) {
        final apiEndDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        if (apiEndDate.isAfter(endDate)) {
          endDate = apiEndDate;
        }
      }
    }

    final daysBack = 364 + endDate.weekday % 7;
    final startDate = endDate.subtract(Duration(days: daysBack));
    final totalDays = endDate.difference(startDate).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final dayMap = {for (var d in apiDays) d.date: d.count};

    // Slightly larger cells for better tap targets & readability
    const cellSize = 12.0;
    const cellGap = 3.0;
    const cellStep = cellSize + cellGap;

    return SingleChildScrollView(
      controller: _scrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels
          _buildMonthLabels(tokens, startDate, endDate, totalWeeks, cellStep),
          const SizedBox(height: 6),

          // Day grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day-of-week labels
              _buildDayLabels(tokens, cellStep),
              const SizedBox(width: 6),

              // Weeks
              for (int w = 0; w < totalWeeks; w++)
                Padding(
                  padding: const EdgeInsets.only(right: 3.0),
                  child: Column(
                    children: List.generate(7, (d) {
                      final offset = w * 7 + d;
                      final date = startDate.add(Duration(days: offset));

                      if (date.isAfter(endDate)) {
                        return SizedBox(width: cellSize, height: cellStep);
                      }

                      final dateStr =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final count = dayMap[dateStr] ?? 0;
                      final intensity = _intensityForCount(count);

                      return GestureDetector(
                        onTapDown: (details) {
                          setState(() {
                            _tooltipText =
                                '${_formatDate(date)} · $count plays';
                            _tooltipOffset = Offset(
                              details.localPosition.dx - 40,
                              -36,
                            );
                          });
                        },
                        onTapUp: (_) => setState(() => _tooltipText = null),
                        onTapCancel: () => setState(() => _tooltipText = null),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.only(bottom: cellGap),
                          decoration: BoxDecoration(
                            color: _colorForIntensity(intensity, tokens),
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  double _intensityForCount(int count) {
    if (count == 0) return 0;
    if (count < 4) return 0.25;
    if (count < 9) return 0.5;
    if (count < 18) return 0.75;
    return 1.0;
  }

  Color _colorForIntensity(double intensity, AppThemeTokens tokens) {
    if (intensity == 0) {
      return tokens.textPrimary.withOpacity(0.07);
    }
    return tokens.accent.withOpacity(0.2 + intensity * 0.8);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _buildMonthLabels(
    AppThemeTokens tokens,
    DateTime startDate,
    DateTime endDate,
    int totalWeeks,
    double cellStep,
  ) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final labels = <Widget>[
      const SizedBox(width: 28), // day label offset
    ];

    int? lastMonth;
    for (int w = 0; w < totalWeeks; w++) {
      final d = startDate.add(Duration(days: w * 7));
      if (d.month != lastMonth) {
        lastMonth = d.month;

        final isFirst = w == 0;
        // Always show year when month is Jan OR when it's the very first label
        // This ensures 2026 months show their year correctly
        final isJan = d.month == 1;
        final showYear = isFirst || isJan || d.year == endDate.year && isFirst;
        final text = showYear
            ? '${months[d.month - 1]} ${d.year}'
            : months[d.month - 1];

        labels.add(
          SizedBox(
            width: cellStep * 4,
            child: Text(
              text,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      } else {
        labels.add(SizedBox(width: cellStep));
      }
    }

    return Row(children: labels);
  }

  Widget _buildDayLabels(AppThemeTokens tokens, double cellStep) {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Column(
      children: List.generate(7, (i) {
        final show = i == 1 || i == 3 || i == 5;
        return SizedBox(
          height: cellStep,
          width: 12,
          child: show
              ? Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    days[i],
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        );
      }),
    );
  }

  Widget _buildLegend(AppThemeTokens tokens) {
    return Row(
      children: [
        Text(
          'Less',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        _LegendSquare(color: tokens.textPrimary.withOpacity(0.07)),
        _LegendSquare(color: tokens.accent.withOpacity(0.25)),
        _LegendSquare(color: tokens.accent.withOpacity(0.50)),
        _LegendSquare(color: tokens.accent.withOpacity(0.75)),
        _LegendSquare(color: tokens.accent),
        const SizedBox(width: 6),
        Text(
          'More',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        _streakBadge(tokens),
      ],
    );
  }

  Widget _streakBadge(AppThemeTokens tokens) {
    final async = ref.read(contributionGraphProvider);
    return async.maybeWhen(
      data: (data) {
        final now = DateTime.now();
        int streak = 0;
        final dayMap = {for (var d in data.days) d.date: d.count};
        for (int i = 0; i <= 365; i++) {
          final d = now.subtract(Duration(days: i));
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          if ((dayMap[key] ?? 0) > 0) {
            streak++;
          } else {
            break;
          }
        }
        if (streak == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tokens.accent.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              Text(
                '$streak day streak',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _LegendSquare extends StatelessWidget {
  final Color color;
  const _LegendSquare({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
  }
}
