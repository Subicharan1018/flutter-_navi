import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../features/ai_shuffle/logic/shuffle_providers.dart';
import '../../widgets/ui/controls.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/states.dart';
import 'widgets/genre_mix.dart';
import 'widgets/hours_chart.dart';
import 'widgets/model_status.dart';
import 'widgets/summary_grid.dart';
import 'widgets/top_lists.dart';
import 'widgets/trend_chart.dart';
import 'widgets/year_grid.dart';

enum StatsPeriod {
  week('7 Days', 'weekly', 7),
  month('30 Days', 'monthly', 30),
  all('All Time', 'all', 90);

  final String label;

  /// Key the stats server expects.
  final String apiValue;

  /// Days the trend chart covers.
  final int trendDays;
  const StatsPeriod(this.label, this.apiValue, this.trendDays);
}

/// Listening statistics, Apple Health style: a period switch, four headline
/// tiles, then one card per question (when, what, how often, how steadily).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.week;

  void _refresh() {
    ref.invalidate(listeningStatsProvider(_period.apiValue));
    ref.invalidate(modelStatusProvider);
    ref.invalidate(contributionGraphProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(listeningStatsProvider(_period.apiValue));
    final model = ref.watch(modelStatusProvider).asData?.value;
    final days = ref.watch(contributionGraphProvider).asData?.value.days ?? const <ContributionDay>[];

    return LargeTitlePage(
      title: 'Stats',
      onRefresh: () async => _refresh(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
          sliver: SliverToBoxAdapter(
            child: NaviSegmented<StatsPeriod>(
              segments: {for (final p in StatsPeriod.values) p: p.label},
              value: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
          ),
        ),
        ...stats.when(
          loading: () => const [SliverToBoxAdapter(child: LoadingState())],
          error: (_, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: MessageState.error(
                title: 'Stats aren’t available',
                message: 'Stats come from your Smart Shuffle server. Check that it’s running, then try again.',
                onRetry: _refresh,
              ),
            ),
          ],
          data: (s) {
            final cards = <Widget>[
              HoursChart(byHour: s.hourlyHeatmap),
              TrendChart(days: days, window: _period.trendDays),
              TopArtistsCard(artists: s.topArtists),
              TopSongsCard(tracks: s.topTracks),
              GenreMixCard(genres: s.genreBreakdown),
              YearGrid(days: days),
              if (model != null) ModelStatusCard(status: model),
            ];
            return [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                sliver: SliverToBoxAdapter(child: SummaryGrid(stats: s, days: days)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
                sliver: SliverLayoutBuilder(builder: (context, c) {
                  // Two columns of cards once there's room, like Health on iPad.
                  if (c.crossAxisExtent < 900) {
                    return SliverList.separated(
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                      itemBuilder: (_, i) => cards[i],
                    );
                  }
                  return SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final column in [0, 1]) ...[
                          if (column == 1) const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              children: [
                                for (var i = column; i < cards.length; i += 2) ...[
                                  cards[i],
                                  const SizedBox(height: Space.md),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ),
            ];
          },
        ),
      ],
    );
  }
}
