import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../features/ai_shuffle/data/models/listening_stats_response.dart';
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
  week('7 Days', 'weekly', 7, 'in the last 7 days'),
  month('30 Days', 'monthly', 30, 'in the last 30 days'),
  all('All Time', 'all', 90, 'all time');

  final String label;

  /// Key the stats server expects.
  final String apiValue;

  /// Days the trend chart covers.
  final int trendDays;

  /// Completes "65h listened …".
  final String phrase;
  const StatsPeriod(this.label, this.apiValue, this.trendDays, this.phrase);
}

/// Listening statistics, set straight on the page like Apple's Fitness and
/// Health summaries: a period switch, time listened as one big figure, then
/// one section per question (when, how often, who, what, how steadily). No
/// cards: type, space and the charts themselves carry the structure.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.week;

  /// The last period that loaded, kept on screen while a newly picked one
  /// loads so the page doesn't blank to a spinner on every switch.
  ListeningStatsResponse? _shown;

  void _refresh() {
    ref.invalidate(listeningStatsProvider(_period.apiValue));
    ref.invalidate(modelStatusProvider);
    ref.invalidate(contributionGraphProvider);
  }

  @override
  Widget build(BuildContext context) {
    var stats = ref.watch(listeningStatsProvider(_period.apiValue));
    if (stats.hasValue) {
      _shown = stats.value;
    } else if (stats.isLoading && _shown != null) {
      stats = AsyncData(_shown!);
    }
    final model = ref.watch(modelStatusProvider).asData?.value;
    final days = ref.watch(contributionGraphProvider).asData?.value.days ?? const <ContributionDay>[];

    return LargeTitlePage(
      title: 'Stats',
      onRefresh: () async => _refresh(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xxl),
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
            final sections = <Widget>[
              ListeningClock(byHour: s.hourlyHeatmap),
              TrendChart(days: days, window: _period.trendDays, totalPlays: s.totalPlays),
              TopArtistsCard(artists: s.topArtists),
              TopSongsCard(tracks: s.topTracks),
              GenreMixCard(genres: s.genreBreakdown),
              YearGrid(days: days),
              if (model != null) ModelStatusCard(status: model),
            ];
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: SummaryHero(stats: s, days: days, periodPhrase: _period.phrase),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                sliver: SliverLayoutBuilder(builder: (context, c) {
                  if (c.crossAxisExtent < 900) return SliverList.list(children: sections);
                  // Two columns once there's room, like Health on iPad.
                  return SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final column in [0, 1]) ...[
                          if (column == 1) const SizedBox(width: Space.huge),
                          Expanded(
                            child: Column(
                              children: [for (var i = column; i < sections.length; i += 2) sections[i]],
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
