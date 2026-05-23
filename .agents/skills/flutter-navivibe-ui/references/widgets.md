# NaviVibe Widget Implementations

## Table of Contents
- Section A: HourlyHeatmap
- Section B: GenreRadarChart
- Section C: ContributionGraph (Calendar Heatmap)
- Section D: ListeningLineChart
- Section E: ModelStatusCard
- Section F: DashboardScreen (full scaffold)

---

## Section A: HourlyHeatmap

Maps `hourly_heatmap: { "0": 0, "8": 12, "21": 42 }` from the stats API.

```dart
class HourlyHeatmap extends StatelessWidget {
  final Map<String, int> heatmapData; // "0"–"23" → count

  const HourlyHeatmap({super.key, required this.heatmapData});

  @override
  Widget build(BuildContext context) {
    final maxCount = heatmapData.values.fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    return NaviCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Listening Hours', style: AppThemeTokens.titleMd),
          const SizedBox(height: s16),
          SizedBox(
            height: 48,
            child: Row(
              children: List.generate(24, (hour) {
                final count = heatmapData[hour.toString()] ?? 0;
                final intensity = maxCount > 0 ? count / maxCount : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      children: [
                        Expanded(
                          child: AnimatedContainer(
                            duration: kAnimSlow,
                            decoration: BoxDecoration(
                              color: AppThemeTokens.primary.withOpacity(
                                0.08 + intensity * 0.75,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (hour % 6 == 0)
                          Text(
                            '$hour',
                            style: AppThemeTokens.labelSm.copyWith(
                              color: AppThemeTokens.onSurfaceMuted,
                              fontSize: 9,
                            ),
                          )
                        else
                          const SizedBox(height: 11),
                      ],
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
```

---

## Section B: GenreRadarChart

Maps `genre_breakdown: [{ genre, play_count, pct }]`.
Requires `fl_chart` package.

```dart
import 'package:fl_chart/fl_chart.dart';

class GenreRadarChart extends StatelessWidget {
  final List<GenreBreakdown> genres;

  const GenreRadarChart({super.key, required this.genres});

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) return const SizedBox.shrink();

    // Take top 6 genres for readability
    final top = genres.take(6).toList();
    final maxPct = top.fold(0.0, (a, b) => a > b.pct ? a : b.pct);

    return NaviCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Genre Mix', style: AppThemeTokens.titleMd),
          const SizedBox(height: s16),
          SizedBox(
            height: 200,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                gridBorderData: BorderSide(
                  color: AppThemeTokens.onSurface.withOpacity(0.1),
                  width: 0.5,
                ),
                tickBorderData: const BorderSide(color: Colors.transparent),
                tickCount: 4,
                titleTextStyle: AppThemeTokens.labelSm.copyWith(
                  color: AppThemeTokens.onSurfaceMuted,
                ),
                getTitle: (index, angle) => RadarChartTitle(
                  text: top[index].genre,
                  angle: angle,
                ),
                dataSets: [
                  RadarDataSet(
                    fillColor: AppThemeTokens.primary.withOpacity(0.12),
                    borderColor: AppThemeTokens.primary,
                    borderWidth: 2,
                    entryRadius: 3,
                    dataEntries: top
                        .map((g) => RadarEntry(value: g.pct / maxPct * 100))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: s12),
          // Legend
          Wrap(
            spacing: s12,
            runSpacing: s8,
            children: top.map((g) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: AppThemeTokens.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${g.genre} ${g.pct.toStringAsFixed(0)}%',
                  style: AppThemeTokens.labelSm.copyWith(
                    color: AppThemeTokens.onSurfaceMuted,
                  ),
                ),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }
}
```

---

## Section C: ContributionGraph (Calendar Heatmap)

Flutter equivalent of the React `ContributionGraph` component.
Uses `recentPlays` data or daily play counts from the history endpoint.

```dart
class ContributionGraph extends StatefulWidget {
  final Map<String, int> dailyPlays; // "2026-05-22" → count

  const ContributionGraph({super.key, required this.dailyPlays});

  @override
  State<ContributionGraph> createState() => _ContributionGraphState();
}

class _ContributionGraphState extends State<ContributionGraph> {
  String? _hoveredDate;

  List<DateTime> _buildWeeks() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 364));
    // align to Sunday
    final startSunday = start.subtract(Duration(days: start.weekday % 7));
    return List.generate(
      53 * 7,
      (i) => startSunday.add(Duration(days: i)),
    );
  }

  int _level(int count) {
    if (count == 0) return 0;
    if (count < 5) return 1;
    if (count < 10) return 2;
    if (count < 20) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildWeeks();
    final maxCount = widget.dailyPlays.values.fold(0, (a, b) => a > b ? a : b);

    return NaviCard(
      padding: const EdgeInsets.all(s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: AppThemeTokens.titleMd),
          const SizedBox(height: s12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month labels
                _MonthLabels(days: days),
                const SizedBox(height: 4),
                // Grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day labels
                    _DayLabels(),
                    const SizedBox(width: 4),
                    // Weeks
                    for (int week = 0; week < 53; week++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Column(
                          children: [
                            for (int day = 0; day < 7; day++)
                              Builder(builder: (_) {
                                final idx = week * 7 + day;
                                if (idx >= days.length) {
                                  return const SizedBox(width: 10, height: 12);
                                }
                                final date = days[idx];
                                final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                final count = widget.dailyPlays[key] ?? 0;
                                final level = _level(count);
                                final isHovered = _hoveredDate == key;

                                return GestureDetector(
                                  onLongPress: () => setState(() =>
                                    _hoveredDate = _hoveredDate == key ? null : key),
                                  child: AnimatedContainer(
                                    duration: kAnimFast,
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      color: level == 0
                                        ? AppThemeTokens.onSurface.withOpacity(0.06)
                                        : AppThemeTokens.primary.withOpacity(level * 0.22),
                                      borderRadius: BorderRadius.circular(2),
                                      border: isHovered
                                        ? Border.all(color: AppThemeTokens.primary, width: 1)
                                        : null,
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Hovered date info
          if (_hoveredDate != null) ...[
            const SizedBox(height: s8),
            Text(
              '${_hoveredDate!}: ${widget.dailyPlays[_hoveredDate!] ?? 0} plays',
              style: AppThemeTokens.labelMd.copyWith(
                color: AppThemeTokens.primary,
              ),
            ),
          ],
          const SizedBox(height: s12),
          // Legend
          Row(
            children: [
              Text('Less', style: AppThemeTokens.labelSm.copyWith(
                color: AppThemeTokens.onSurfaceMuted,
              )),
              const SizedBox(width: s8),
              for (int i = 0; i <= 4; i++)
                Container(
                  width: 10, height: 10,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i == 0
                      ? AppThemeTokens.onSurface.withOpacity(0.06)
                      : AppThemeTokens.primary.withOpacity(i * 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: s8),
              Text('More', style: AppThemeTokens.labelSm.copyWith(
                color: AppThemeTokens.onSurfaceMuted,
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  final List<DateTime> days;
  const _MonthLabels({required this.days});

  @override
  Widget build(BuildContext context) {
    // Show month label at start of each month column
    final labels = <Widget>[const SizedBox(width: 20)]; // offset for day labels
    int? lastMonth;
    for (int week = 0; week < 53; week++) {
      final idx = week * 7;
      if (idx < days.length) {
        final month = days[idx].month;
        if (month != lastMonth) {
          lastMonth = month;
          labels.add(SizedBox(
            width: 12 * (52 - week + 1).clamp(1, 6).toDouble(),
            child: Text(
              ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month - 1],
              style: AppThemeTokens.labelSm.copyWith(
                color: AppThemeTokens.onSurfaceMuted,
                fontSize: 9,
              ),
            ),
          ));
        } else {
          labels.add(const SizedBox(width: 12));
        }
      }
    }
    return Row(children: labels);
  }
}

class _DayLabels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const days = ['S','M','T','W','T','F','S'];
    return Column(
      children: List.generate(7, (i) => SizedBox(
        height: 12,
        child: i % 2 == 1 ? Text(
          days[i],
          style: AppThemeTokens.labelSm.copyWith(
            color: AppThemeTokens.onSurfaceMuted,
            fontSize: 9,
          ),
        ) : null,
      )),
    );
  }
}
```

---

## Section D: ListeningLineChart

Pinging dot line chart, equivalent of the React `PingingDotChart`.
Requires `fl_chart`.

```dart
import 'package:fl_chart/fl_chart.dart';

class ListeningLineChart extends StatelessWidget {
  final List<FlSpot> spots;   // x=day index, y=play count
  final List<String> labels;  // date labels for x axis

  const ListeningLineChart({super.key, required this.spots, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    return NaviCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Listening Over Time', style: AppThemeTokens.titleMd),
          const SizedBox(height: s16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppThemeTokens.onSurface.withOpacity(0.06),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (spots.length / 4).ceilToDouble(),
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                        return Text(
                          labels[idx],
                          style: AppThemeTokens.labelSm.copyWith(
                            color: AppThemeTokens.onSurfaceMuted,
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
                    color: AppThemeTokens.primary,
                    strokeWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => _PingingDotPainter(
                        color: AppThemeTokens.primary,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppThemeTokens.primary.withOpacity(0.15),
                          AppThemeTokens.primary.withOpacity(0.0),
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

// Custom pinging dot painter — equivalent of React SVG ping animation
class _PingingDotPainter extends FlDotPainter {
  final Color color;
  _PingingDotPainter({required this.color});

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    // Main dot
    canvas.drawCircle(offsetInCanvas, 3, Paint()..color = color);
    // Ping ring
    canvas.drawCircle(
      offsetInCanvas, 6,
      Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  Size getSize(FlSpot spot) => const Size(12, 12);

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;
}
```

---

## Section E: ModelStatusCard

Shows rebuild progress, songs in library, unprocessed events.

```dart
class ModelStatusCard extends StatelessWidget {
  final ModelStatusResponse status;

  const ModelStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return NaviCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AI Model', style: AppThemeTokens.titleMd),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: s8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppThemeTokens.success.withOpacity(0.12),
                  borderRadius: radiusFull,
                ),
                child: Text(
                  'Active',
                  style: AppThemeTokens.labelSm.copyWith(
                    color: AppThemeTokens.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: s16),
          // Stats row
          Row(
            children: [
              _ModelStat(label: 'Songs', value: '${status.songsInLibrary}'),
              _ModelStat(label: 'Plays', value: '${status.totalPlaysProcessed}'),
              _ModelStat(label: 'Composers', value: '${status.composersTracked}'),
              _ModelStat(label: 'Contexts', value: '${status.contextBuckets}'),
            ],
          ),
          const SizedBox(height: s16),
          // Rebuild progress
          Row(
            children: [
              Text(
                'Rebuild progress',
                style: AppThemeTokens.labelMd.copyWith(
                  color: AppThemeTokens.onSurfaceMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${status.unprocessedEvents}/${status.rebuildThreshold}',
                style: AppThemeTokens.mono.copyWith(
                  color: AppThemeTokens.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: s8),
          ClipRRect(
            borderRadius: radiusFull,
            child: LinearProgressIndicator(
              value: status.rebuildProgress,
              backgroundColor: AppThemeTokens.onSurface.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(
                status.rebuildProgress > 0.8
                  ? AppThemeTokens.warning
                  : AppThemeTokens.primary,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: s8),
          Text(
            'Model size: ${status.modelSizeMb.toStringAsFixed(1)} MB',
            style: AppThemeTokens.labelSm.copyWith(
              color: AppThemeTokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelStat extends StatelessWidget {
  final String label;
  final String value;
  const _ModelStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppThemeTokens.titleLg.copyWith(
            fontFeatures: [const FontFeature.tabularFigures()],
          )),
          Text(label, style: AppThemeTokens.labelSm.copyWith(
            color: AppThemeTokens.onSurfaceMuted,
          )),
        ],
      ),
    );
  }
}
```

---

## Section F: DashboardScreen (full scaffold)

```dart
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  StatsPeriod _period = StatsPeriod.weekly;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider(_period));
    final modelAsync = ref.watch(modelStatusProvider);

    return Scaffold(
      backgroundColor: AppThemeTokens.surfaceVariant,
      body: CustomScrollView(
        slivers: [
          // Collapsible header
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppThemeTokens.surface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text('Your Stats', style: AppThemeTokens.titleLg),
            ),
          ),

          // Period selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(s16, s16, s16, 0),
              child: _PeriodSelector(
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ),
          ),

          // Content
          statsAsync.when(
            data: (stats) => SliverPadding(
              padding: const EdgeInsets.all(s16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildMetricsGrid(stats),
                  const SizedBox(height: s16),
                  HourlyHeatmap(heatmapData: stats.hourlyHeatmap),
                  const SizedBox(height: s16),
                  GenreRadarChart(genres: stats.genreBreakdown),
                  const SizedBox(height: s16),
                  ContributionGraph(dailyPlays: _buildDailyMap(stats)),
                  const SizedBox(height: s16),
                  _TopArtistsList(artists: stats.topArtists),
                  const SizedBox(height: s16),
                  _TopTracksList(tracks: stats.topTracks),
                  const SizedBox(height: s16),
                  modelAsync.when(
                    data: (m) => ModelStatusCard(status: m),
                    loading: () => const NaviSkeleton(height: 160),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: s32),
                ]),
              ),
            ),
            loading: () => SliverPadding(
              padding: const EdgeInsets.all(s16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const NaviSkeleton(height: 120),
                  const SizedBox(height: s16),
                  const NaviSkeleton(height: 80),
                  const SizedBox(height: s16),
                  const NaviSkeleton(height: 200),
                ]),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: _buildError(e),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _buildDailyMap(ListeningStatsResponse stats) {
    // Aggregate recentPlays by date for contribution graph
    final map = <String, int>{};
    for (final play in stats.recentPlays) {
      final date = play.playedAtIst.substring(0, 10);
      map[date] = (map[date] ?? 0) + 1;
    }
    return map;
  }

  Widget _buildError(Object e) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: AppThemeTokens.error, size: 40),
          const SizedBox(height: s16),
          Text('Could not load stats', style: AppThemeTokens.titleMd),
          const SizedBox(height: s8),
          LiquidGlassButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: () => ref.invalidate(statsProvider(_period)),
          ),
        ],
      ),
    );
  }
}
```
