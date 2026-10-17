import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/trending_models.dart';
import '../logic/trending_providers.dart';
import 'chart_actions.dart';
import 'widgets/chart_row.dart';

/// The Trending page: the charts as pills, the picked chart's 50
/// songs ranked with their movement, and Play / Shuffle for the whole chart.
class TrendingScreen extends ConsumerWidget {
  const TrendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendingChartsProvider);
    final charts = async.asData?.value;
    final chart = charts == null ? null : pickChart(charts, ref.watch(selectedChartProvider));
    return LargeTitlePage(
      title: 'Trending',
      header: chart == null ? null : ChartPills(charts: charts!, selected: chart.key),
      onRefresh: () => ref.refresh(trendingChartsProvider.future),
      slivers: [
        if (chart != null) ...[
          SliverToBoxAdapter(child: _ChartHeader(chart: chart)),
          SliverList.builder(
            itemCount: chart.entries.length,
            itemBuilder: (context, i) => ChartRow(
              entry: chart.entries[i],
              showSeparator: i < chart.entries.length - 1,
              onTap: () => playFromChart(context, ref, chart, chart.entries[i]),
            ),
          ),
        ] else
          SliverToBoxAdapter(
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: Space.sm),
                child: TrackListSkeleton(rows: 10),
              ),
              error: (e, _) => MessageState.error(
                title: 'Charts didn’t load',
                message: '$e',
                onRetry: () => ref.invalidate(trendingChartsProvider),
              ),
              data: (_) => const MessageState(
                icon: CupertinoIcons.chart_bar_alt_fill,
                title: 'No charts yet',
                message: 'The server collects today’s charts after 4 AM. Pull down to check again.',
              ),
            ),
          ),
      ],
    );
  }
}

/// The charts as filter pills (Home and the Trending page share the pick).
class ChartPills extends ConsumerWidget {
  final TrendingCharts charts;
  final String selected;
  const ChartPills({super.key, required this.charts, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilterPills<String>(
      options: {for (final c in charts.withSongs) c.key: c.title},
      value: selected,
      onChanged: ref.read(selectedChartProvider.notifier).select,
    );
  }
}

/// What the chart is, when it was updated, how much of it is in the
/// library, then Play / Shuffle.
class _ChartHeader extends ConsumerWidget {
  final TrendingChart chart;
  const _ChartHeader({required this.chart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final playable = chart.playableCount;
    final lines = [
      [chart.source, chartDateLine(chart.date)].where((s) => s.isNotEmpty).join(' · '),
      '$playable of ${chart.entries.length} in your library',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines) Text(l, style: t.footnote),
          if (chart.note != null) ...[
            const SizedBox(height: Space.xs),
            Text(chart.note!, style: t.footnote.copyWith(color: t.textMuted)),
          ],
          const SizedBox(height: Space.lg),
          Center(
            child: PlayShuffleButtons(
              onPlay: playable == 0 ? null : () => playChart(context, ref, chart),
              onShuffle: playable == 0 ? null : () => playChart(context, ref, chart, shuffle: true),
            ),
          ),
        ],
      ),
    );
  }
}
