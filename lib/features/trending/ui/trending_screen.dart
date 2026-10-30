import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/trending_models.dart';
import '../logic/trending_providers.dart';
import '../../online_fetch/logic/online_fetch_providers.dart' show onlineFetchEnabledProvider;
import '../../online_fetch/ui/queue_playlist_button.dart';
import 'chart_actions.dart';
import 'widgets/chart_details.dart' show BillboardColumns;
import 'widgets/chart_row.dart';
import 'widgets/expandable_chart_row.dart';

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
      // The pills pad themselves to the gutter and scroll edge to edge.
      headerPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      onRefresh: () => ref.refresh(trendingChartsProvider.future),
      slivers: [
        if (chart != null) ...[
          SliverToBoxAdapter(child: _ChartHeader(chart: chart)),
          SliverList.builder(
            itemCount: chart.entries.length,
            itemBuilder: (context, i) => ExpandableChartRow(
              // Open rows close when the chart changes.
              key: ValueKey('${chart.key}/${chart.entries[i].rank}'),
              entry: chart.entries[i],
              showSeparator: i < chart.entries.length - 1,
              onPlay: () => playFromChart(context, ref, chart, chart.entries[i]),
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
                icon: NaviGlyph.trending,
                art: EmptyArtKind.signal,
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
    final columns = chart.kind == ChartKind.billboard && MediaQuery.sizeOf(context).width >= ChartRow.columnsFrom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Billboard's chart week leads, as on billboard.com.
          if (chart.weekOf != null) ...[
            Text('Week of ${chart.weekOf}', style: t.headline),
            const SizedBox(height: Space.xxs),
          ],
          for (final l in lines) Text(l, style: t.footnote),
          if (chart.description != null) ...[
            const SizedBox(height: Space.xs),
            Text(chart.description!, style: t.footnote.copyWith(color: t.textMuted)),
          ],
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
          if (chart.playlistLink != null && (ref.watch(onlineFetchEnabledProvider).asData?.value ?? false)) ...[
            const SizedBox(height: Space.md),
            Center(child: QueuePlaylistButton(link: chart.playlistLink!)),
          ],
          if (columns) ...[
            const SizedBox(height: Space.md),
            // Above the rows' LW · PEAK · WKS, clear of the chevron.
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(padding: EdgeInsets.only(right: 22), child: BillboardColumns.header()),
            ),
          ],
        ],
      ),
    );
  }
}
