import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../features/ai_shuffle/logic/shuffle_providers.dart';
import '../../providers/library_provider.dart' show artistCoverUrlProvider;
import '../../utils/platform_utils.dart';
import '../../widgets/ui/controls.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/sliver_width_builder.dart';
import '../../widgets/motion/reveal.dart';
import '../../widgets/ui/states.dart';
import 'widgets/fortnight_chart.dart';
import 'widgets/genre_mix.dart';
import 'widgets/hours_chart.dart';
import 'widgets/model_status.dart';
import 'widgets/summary_grid.dart';
import 'widgets/top_lists.dart';
import 'widgets/trend_chart.dart';
import 'widgets/year_grid.dart';

enum StatsPeriod {
  // The server's weekly and monthly periods are the calendar week (from
  // Monday) and month, not the last 7 and 30 days, so the page says so.
  week('This Week', 'weekly', 7, 'this week'),
  month('This Month', 'monthly', 30, 'this month'),
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

  /// The last response and the period it is for, kept on screen (dimmed, under
  /// its own name) while a newly picked one loads, so the page doesn't blank to
  /// a spinner on every switch. Its numbers are never labelled as another
  /// period's.
  ({StatsPeriod period, ListeningStatsResponse data})? _last;

  void _refresh() {
    ref.invalidate(listeningStatsProvider(_period.apiValue));
    ref.invalidate(modelStatusProvider);
    ref.invalidate(contributionGraphProvider);
  }

  @override
  Widget build(BuildContext context) {
    var stats = ref.watch(listeningStatsProvider(_period.apiValue));
    var shown = _period;
    var waiting = false;
    if (stats.hasValue) {
      _last = (period: _period, data: stats.requireValue);
    } else if (!stats.hasError && _last != null) {
      // Not `isLoading`: that stays true while a failed request is retried.
      waiting = true;
      shown = _last!.period;
      stats = AsyncData(_last!.data);
    } else if (stats.hasError) {
      stats = AsyncError(stats.error!, stats.stackTrace!);
    }
    final model = ref.watch(modelStatusProvider).asData?.value;
    final days = ref.watch(contributionGraphProvider).asData?.value.days ?? const <ContributionDay>[];

    final desk = PlatformUtils.isDesktop;
    final g = desk ? pageGutter(context) : Space.gutter; // one page margin on Windows
    return LargeTitlePage(
      title: 'Stats',
      onRefresh: () async => _refresh(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, Space.sm, g, Space.xxl),
          sliver: SliverToBoxAdapter(
            // Windows: the period switch is a control at the left, not a page-wide bar.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desk ? 420 : double.infinity),
                    child: NaviSegmented<StatsPeriod>(
                      segments: {for (final p in StatsPeriod.values) p: p.label},
                      value: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                  ),
                ),
                if (waiting)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          const CupertinoActivityIndicator(radius: 8),
                          const SizedBox(width: Space.sm),
                          Text('Loading ${_period.label}…', style: ThemeTokens.of(context).footnote),
                        ],
                      ),
                    ),
                  ),
              ],
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
                illustration: 'analytics',
              ),
            ),
          ],
          data: (s) {
            final topName = s.topArtists.isEmpty ? null : s.topArtists.first['artist']?.toString();
            // Each section eases in once, the first time it scrolls into view.
            final sections = <Widget>[
              for (final (i, w) in <Widget>[
                FortnightChart(days: days),
                ListeningClock(byHour: s.hourlyHeatmap),
                TrendChart(days: days, window: shown.trendDays, totalPlays: s.totalPlays),
                TopArtistsCard(artists: s.topArtists),
                TopSongsCard(tracks: s.topTracks),
                GenreMixCard(genres: s.genreBreakdown),
                YearGrid(days: days),
                if (model != null) ModelStatusCard(status: model),
              ].indexed)
                Reveal(key: ValueKey('${shown.name}-$i'), index: i < 2 ? i : 0, child: RepaintBoundary(child: w)),
            ];
            return [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, Space.sm, g, 0),
                sliver: SliverToBoxAdapter(
                  child: SummaryHero(
                    stats: s,
                    periodPhrase: shown.phrase,
                    history: days,
                    topArtist: topName,
                    topArtistCover: topName == null ? null : ref.watch(artistCoverUrlProvider(topName)).asData?.value,
                    dailyPlays: [for (final d in days.skip(days.length - shown.trendDays.clamp(7, 30).clamp(0, days.length))) d.count.toDouble()],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: g),
                sliver: SliverWidthBuilder(builder: (context, width) {
                  if (width < 900) return SliverList.list(children: sections);
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
