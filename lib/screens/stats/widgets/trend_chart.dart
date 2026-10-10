import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// Plays per day across the period, compared with the period before it.
class TrendChart extends StatelessWidget {
  final List<ContributionDay> days;
  final int window;

  /// The period's total from the stats endpoint. When the server has plays
  /// but no daily series, the chart steps aside instead of claiming there's
  /// no listening.
  final int totalPlays;
  const TrendChart({super.key, required this.days, required this.window, required this.totalPlays});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final byDate = {for (final d in days) d.date: d.count};
    final now = DateTime.now();
    int playsOn(int daysAgo) => byDate[isoDate(now.subtract(Duration(days: daysAgo)))] ?? 0;

    final spots = [for (var i = 0; i < window; i++) FlSpot(i.toDouble(), playsOn(window - 1 - i).toDouble())];
    final current = spots.fold<double>(0, (s, p) => s + p.y);
    var previous = 0;
    for (var i = window; i < window * 2; i++) {
      previous += playsOn(i);
    }

    if (current == 0 && previous == 0) {
      if (totalPlays > 0) return const SizedBox.shrink();
      return StatSection(
        title: 'Plays per Day',
        child: Text('Play some music and your daily listening is drawn here.', style: t.subheadline),
      );
    }

    final change = previous == 0 ? null : ((current - previous) / previous * 100).round();
    final up = (change ?? 0) >= 0;
    DateTime dateFor(int i) => now.subtract(Duration(days: window - 1 - i));
    String short(DateTime d) => '${_months[d.month - 1]} ${d.day}';

    return StatSection(
      title: 'Plays per Day',
      readout: change == null ? compactCount(current.round()) : '${up ? '+' : ''}$change%',
      readoutColor: change == null ? null : (up ? t.positive : t.danger),
      readoutCaption: change == null ? 'plays' : 'vs the previous $window days',
      child: SizedBox(
        height: 170,
        child: LineChart(
          LineChartData(
            minY: 0,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: t.separatorOpaque, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, meta) => v == meta.max
                      ? Padding(
                          padding: const EdgeInsets.only(left: Space.xs),
                          child: Text(v.toInt().toString(), style: t.caption2),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: (window / 4).ceilToDouble(),
                  // Kept inside the plot so the first and last dates never
                  // hang past the page margin.
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    space: Space.xs + 2,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(short(dateFor(v.toInt())), style: t.caption2),
                  ),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => t.bgElevated,
                tooltipBorderRadius: BorderRadius.circular(Radii.control),
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${short(dateFor(s.x.toInt()))}\n',
                      t.caption1,
                      children: [
                        TextSpan(
                          text: s.y == 1 ? '1 play' : '${s.y.toInt()} plays',
                          style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: t.accent,
                barWidth: 2.5,
                dotData: FlDotData(checkToShowDot: (s, _) => s.x == spots.last.x),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Solid steps from a deep green to the page: no transparency.
                    colors: [Color.lerp(t.bgBase, t.accent, 0.24)!, t.bgBase],
                  ),
                ),
              ),
            ],
          ),
          duration: Motion.slow,
          curve: Motion.ease,
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}
