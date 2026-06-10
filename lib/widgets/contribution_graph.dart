import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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

  // Tooltip & selection state
  String? _selectedDate;
  int? _selectedCount;
  int? _selectedWeek;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (_scrollRetries < 3) {
        _scrollRetries++;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    }
  }

  Animation<double> _getCellAnim(int w, int totalWeeks) {
    if (MediaQuery.of(context).disableAnimations) {
      return const AlwaysStoppedAnimation(1.0);
    }
    final start = (w / totalWeeks) * 0.7;
    final end = (start + 0.3).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _animCtrl,
      curve: Interval(start, end, curve: Curves.easeOutQuint),
    );
  }

  String _formatDateRange(String? start, String? end) {
    if (start == null || end == null) return '';
    final startStr = _formatMonthYear(start);
    final endStr = _formatMonthYear(end);
    if (startStr.isEmpty || endStr.isEmpty) return '';
    return '$startStr – $endStr';
  }

  String _formatMonthYear(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return '';
    final year = parts[0];
    final monthInt = int.tryParse(parts[1]) ?? 1;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (monthInt < 1 || monthInt > 12) return '';
    return '${months[monthInt - 1]} $year';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final asyncData = ref.watch(contributionGraphProvider);

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(s20, s24, s20, s20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedDate != null) {
            setState(() {
              _selectedDate = null;
              _selectedCount = null;
              _selectedWeek = null;
              _selectedDay = null;
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            asyncData.maybeWhen(
              data: (data) {
                final total = data.days.fold(
                  0,
                  (sum, day) => sum + day.count,
                );
                final formattedRange = _formatDateRange(
                  data.days.firstOrNull?.date,
                  data.days.lastOrNull?.date,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listening consistency',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatNumberWithCommas(total)} plays · $formattedRange',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: tokens.textMuted,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _streakBadge(tokens),
                  ],
                );
              },
              orElse: () => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Listening consistency',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
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
              loading: () => const NaviSkeleton(height: 124),
              error: (e, stack) => Container(
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(s8),
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
            ),

            const SizedBox(height: s16),
            _buildLegend(tokens),
          ],
        ),
      ),
    );
  }

  String _formatNumberWithCommas(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Widget _buildGraph(
    BuildContext context,
    AppThemeTokens tokens,
    List<ContributionDay> apiDays,
  ) {
    final now = DateTime.now();
    DateTime endDate = DateTime(now.year, now.month, now.day);

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

    const cellSize = 12.0;
    const cellGap = 3.0;
    const cellStep = cellSize + cellGap; // 15.0

    return SingleChildScrollView(
      controller: _scrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedDate != null) {
            setState(() {
              _selectedDate = null;
              _selectedCount = null;
              _selectedWeek = null;
              _selectedDay = null;
            });
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month labels (Stack layout, perfectly aligned)
                _buildMonthLabels(tokens, startDate, endDate, totalWeeks, cellStep),
                const SizedBox(height: 6),

                // Day grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day-of-week labels
                    _buildDayLabels(tokens, cellStep),
                    const SizedBox(width: 6),

                    // Weeks (staggered animated columns)
                    for (int w = 0; w < totalWeeks; w++)
                      FadeTransition(
                        opacity: _getCellAnim(w, totalWeeks),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.3, end: 1.0).animate(
                            _getCellAnim(w, totalWeeks),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 3.0),
                            child: Column(
                              children: List.generate(7, (d) {
                                final offset = w * 7 + d;
                                final date = startDate.add(Duration(days: offset));

                                if (date.isAfter(endDate)) {
                                  return const SizedBox(width: cellSize, height: cellStep);
                                }

                                final dateStr =
                                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                final count = dayMap[dateStr] ?? 0;
                                final intensity = _intensityForCount(count);
                                final isSelected = _selectedDate == dateStr;

                                return _buildCell(
                                  w,
                                  d,
                                  dateStr,
                                  count,
                                  intensity,
                                  isSelected,
                                  tokens,
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Correctly positioned interactive tooltip
            if (_selectedDate != null && _selectedWeek != null && _selectedDay != null)
              Positioned(
                left: 18.0 + _selectedWeek! * cellStep + cellSize / 2, // Center of cell horizontally
                top: 16.0 + 6.0 + _selectedDay! * cellStep - 6.0, // Above cell with gap
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -1.0),
                  child: _buildTooltip(
                    DateTime.parse(_selectedDate!),
                    _selectedCount!,
                    tokens,
                  ),
                ),
              ),
          ],
        ),
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

  Widget _buildCell(
    int w,
    int d,
    String dateStr,
    int count,
    double intensity,
    bool isSelected,
    AppThemeTokens tokens,
  ) {
    final mode = tokens.mode;
    
    double size = 12.0;
    BorderRadius radius = BorderRadius.circular(2.5);
    Color color = tokens.textPrimary.withValues(alpha: 0.07);
    BoxBorder? border;
    List<BoxShadow>? shadow;

    if (intensity == 0) {
      switch (mode) {
        case AppThemeMode.spotify:
          color = tokens.textPrimary.withValues(alpha: 0.07);
          radius = BorderRadius.circular(2.5);
          break;
        case AppThemeMode.aura:
          color = tokens.textPrimary.withValues(alpha: 0.05);
          radius = BorderRadius.circular(3.5);
          break;
        case AppThemeMode.frost:
          color = Colors.white.withValues(alpha: 0.06);
          radius = BorderRadius.circular(3.0);
          border = Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5);
          break;
        case AppThemeMode.neumorphic:
          color = tokens.bgBase;
          radius = BorderRadius.circular(3.0);
          border = Border.all(color: tokens.outline.withValues(alpha: 0.15), width: 0.5);
          shadow = [
            BoxShadow(
              color: tokens.neuDark.withValues(alpha: 0.2),
              offset: const Offset(0.5, 0.5),
              blurRadius: 1,
            ),
            BoxShadow(
              color: tokens.neuLight,
              offset: const Offset(-0.5, -0.5),
              blurRadius: 1,
            ),
          ];
          break;
        case AppThemeMode.analog:
          color = tokens.textPrimary.withValues(alpha: 0.06);
          radius = BorderRadius.circular(6.0);
          border = Border.all(color: tokens.outline.withValues(alpha: 0.25), width: 0.5);
          break;
        case AppThemeMode.zen:
          color = tokens.textPrimary.withValues(alpha: 0.04);
          radius = BorderRadius.zero;
          border = Border.all(color: tokens.outline.withValues(alpha: 0.1), width: 0.5);
          break;
      }
    } else {
      switch (mode) {
        case AppThemeMode.spotify:
          color = tokens.accent.withValues(alpha: 0.2 + intensity * 0.8);
          radius = BorderRadius.circular(2.5);
          break;
        case AppThemeMode.aura:
          color = tokens.accent.withValues(alpha: 0.25 + intensity * 0.75);
          radius = BorderRadius.circular(3.5);
          shadow = [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.22 * intensity),
              blurRadius: 4.0 * intensity,
              spreadRadius: 0.5 * intensity,
            ),
          ];
          break;
        case AppThemeMode.frost:
          color = tokens.accent.withValues(alpha: 0.2 + intensity * 0.8);
          radius = BorderRadius.circular(3.0);
          border = Border.all(color: Colors.white.withValues(alpha: 0.3 * intensity), width: 0.5);
          shadow = [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.1 * intensity),
              blurRadius: 3.0,
            )
          ];
          break;
        case AppThemeMode.neumorphic:
          color = Color.lerp(tokens.bgBase, tokens.accent, 0.15 + intensity * 0.85)!;
          radius = BorderRadius.circular(3.0);
          shadow = [
            BoxShadow(
              color: tokens.neuDark.withValues(alpha: 0.35 * intensity),
              offset: Offset(1.0 * intensity, 1.0 * intensity),
              blurRadius: 2.0 * intensity,
            ),
            BoxShadow(
              color: tokens.neuLight.withValues(alpha: 0.9 * intensity),
              offset: Offset(-1.0 * intensity, -1.0 * intensity),
              blurRadius: 2.0 * intensity,
            ),
          ];
          break;
        case AppThemeMode.analog:
          color = tokens.accent.withValues(alpha: 0.25 + intensity * 0.75);
          radius = BorderRadius.circular(6.0);
          border = Border.all(color: tokens.outline.withValues(alpha: 0.4), width: 0.5);
          break;
        case AppThemeMode.zen:
          color = tokens.textPrimary.withValues(alpha: 0.15 + intensity * 0.85);
          radius = BorderRadius.zero;
          border = Border.all(color: tokens.textPrimary, width: 0.5);
          break;
      }
    }

    if (isSelected) {
      if (mode == AppThemeMode.zen) {
        border = Border.all(color: tokens.textPrimary, width: 1.5);
      } else {
        border = Border.all(
          color: tokens.textPrimary,
          width: 1.2,
        );
        shadow = [
          BoxShadow(
            color: tokens.textPrimary.withValues(alpha: 0.4),
            blurRadius: 4.0,
            spreadRadius: 1.0,
          )
        ];
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectedDate == dateStr) {
            _selectedDate = null;
            _selectedCount = null;
            _selectedWeek = null;
            _selectedDay = null;
          } else {
            _selectedDate = dateStr;
            _selectedCount = count;
            _selectedWeek = w;
            _selectedDay = d;
          }
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: isSelected ? 1.25 : 1.0,
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            margin: const EdgeInsets.only(bottom: 3.0),
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
              border: border,
              boxShadow: shadow,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _buildTooltip(DateTime date, int count, AppThemeTokens tokens) {
    final mode = tokens.mode;
    
    Color tooltipBg;
    Color tooltipBorder;
    BorderRadius borderRadius = BorderRadius.circular(6.0);
    List<BoxShadow> shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.15),
        blurRadius: 6.0,
        offset: const Offset(0, 3),
      ),
    ];

    switch (mode) {
      case AppThemeMode.spotify:
        tooltipBg = tokens.bgElevated;
        tooltipBorder = tokens.outline;
        break;
      case AppThemeMode.aura:
        tooltipBg = tokens.bgElevated;
        tooltipBorder = tokens.accent.withValues(alpha: 0.3);
        shadow = [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.15),
            blurRadius: 8.0,
            offset: const Offset(0, 4),
          ),
        ];
        break;
      case AppThemeMode.frost:
        tooltipBg = tokens.bgElevated.withValues(alpha: 0.85);
        tooltipBorder = tokens.glassBorder;
        break;
      case AppThemeMode.neumorphic:
        tooltipBg = tokens.bgSurface;
        tooltipBorder = tokens.outline;
        shadow = [
          BoxShadow(
            color: tokens.neuDark.withValues(alpha: 0.25),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: tokens.neuLight,
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
        ];
        break;
      case AppThemeMode.analog:
        tooltipBg = tokens.bgElevated;
        tooltipBorder = tokens.outline;
        break;
      case AppThemeMode.zen:
        tooltipBg = tokens.bgBase;
        tooltipBorder = tokens.textPrimary;
        borderRadius = BorderRadius.zero;
        shadow = [];
        break;
    }

    final dateText = _formatDate(date);
    final countText = '$count ${count == 1 ? 'play' : 'plays'}';

    Widget tooltipContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tooltipBg,
        borderRadius: borderRadius,
        border: Border.all(color: tooltipBorder, width: 0.8),
        boxShadow: shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateText,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 10,
            color: tokens.textPrimary.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 6),
          Text(
            countText,
            style: TextStyle(
              color: mode == AppThemeMode.zen ? tokens.textPrimary : tokens.accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    if (mode == AppThemeMode.frost) {
      tooltipContent = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: tooltipContent,
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        tooltipContent,
        Positioned(
          bottom: -4,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tooltipBg,
                border: Border(
                  right: BorderSide(color: tooltipBorder, width: 0.8),
                  bottom: BorderSide(color: tooltipBorder, width: 0.8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthLabels(
    AppThemeTokens tokens,
    DateTime startDate,
    DateTime endDate,
    int totalWeeks,
    double cellStep,
  ) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final children = <Widget>[];

    int? lastMonth;
    for (int w = 0; w < totalWeeks; w++) {
      final d = startDate.add(Duration(days: w * 7));
      if (d.month != lastMonth) {
        lastMonth = d.month;

        final isFirst = w == 0;
        final isJan = d.month == 1;
        final showYear = isFirst || isJan;
        final text = showYear
            ? '${months[d.month - 1]} \'${d.year % 100}'
            : months[d.month - 1];

        children.add(
          Positioned(
            left: 18.0 + w * cellStep,
            top: 0,
            child: Text(
              text,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        );
      }
    }

    return SizedBox(
      height: 16.0,
      width: 18.0 + totalWeeks * cellStep,
      child: Stack(
        clipBehavior: Clip.none,
        children: children,
      ),
    );
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
        _LegendSquare(color: tokens.textPrimary.withValues(alpha: 0.07)),
        _LegendSquare(color: tokens.accent.withValues(alpha: 0.25)),
        _LegendSquare(color: tokens.accent.withValues(alpha: 0.50)),
        _LegendSquare(color: tokens.accent.withValues(alpha: 0.75)),
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
            color: tokens.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tokens.accent.withValues(alpha: 0.2),
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

