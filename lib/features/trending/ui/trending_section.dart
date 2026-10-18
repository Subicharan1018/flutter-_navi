import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/trending_models.dart';
import '../logic/trending_providers.dart';
import 'chart_actions.dart';
import 'trending_screen.dart';
import 'widgets/chart_row.dart';

/// Home's Trending shelf, Apple Music's "Top Songs" layout: the chart pills,
/// then the top 20 as swipeable columns of four ranked rows. The title leads
/// to the full Trending page. Renders nothing while there are no charts yet.
class TrendingSection extends ConsumerWidget {
  static const int rowsPerColumn = 4;
  static const int shown = 20;

  const TrendingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendingChartsProvider);
    final header = SectionHeader(title: 'Trending', onTap: () => navigateInApp(context, const TrendingScreen()));
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const TrackListSkeleton(rows: rowsPerColumn)],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          InlineError(message: 'Charts didn’t load. $e', onRetry: () => ref.invalidate(trendingChartsProvider)),
        ],
      ),
      data: (charts) {
        final chart = pickChart(charts, ref.watch(selectedChartProvider));
        if (chart == null) return const SizedBox.shrink();
        final t = ThemeTokens.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            ChartPills(charts: charts, selected: chart.key),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.xs),
              child: Text(
                [chart.source, chartDateLine(chart.date)].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.footnote,
              ),
            ),
            _ChartColumns(chart: chart),
          ],
        );
      },
    );
  }
}

class _ChartColumns extends ConsumerWidget {
  final TrendingChart chart;
  const _ChartColumns({required this.chart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = chart.entries.take(TrendingSection.shown).toList();
    final columns = (top.length / TrendingSection.rowsPerColumn).ceil();
    // A column a little narrower than the page, so the next one peeks in.
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 520.0) * 0.88;
    return SizedBox(
      height: ChartRow.height * TrendingSection.rowsPerColumn,
      child: ListView.builder(
        // A fresh list per chart, so switching charts starts at rank 1.
        key: ValueKey(chart.key),
        scrollDirection: Axis.horizontal,
        itemExtent: width,
        itemCount: columns,
        itemBuilder: (context, c) {
          final rows = top.skip(c * TrendingSection.rowsPerColumn).take(TrendingSection.rowsPerColumn).toList();
          return Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                ChartRow(
                  entry: rows[i],
                  showSeparator: i < rows.length - 1,
                  onTap: () => playFromChart(context, ref, chart, rows[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}
