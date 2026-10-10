import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// The top of Stats: time listened as one big figure, the way Apple Fitness
/// leads with the number you care about. Plays, skips and streak sit under
/// it as supporting figures, then the last two weeks as a strip of days.
class SummaryHero extends StatelessWidget {
  final ListeningStatsResponse stats;
  final List<ContributionDay> days;

  /// "in the last 7 days", "all time"…
  final String periodPhrase;

  const SummaryHero({super.key, required this.stats, required this.days, required this.periodPhrase});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final skip = (stats.skipRate * 100).round().clamp(0, 100);
    // Only a skip rate that says something's off is worth colouring.
    final skipColor = skip > 30 ? t.danger : t.textPrimary;

    return Semantics(
      container: true,
      label: '${listeningTime(stats.totalMinutes)} listened $periodPhrase. '
          '${stats.totalPlays} plays, $skip percent skipped, ${stats.streakDays} day streak.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _Counting(
                target: stats.totalMinutes,
                format: listeningTime,
                style: figureStyle(t, 64).copyWith(color: t.accent, letterSpacing: -2.4),
              ),
            ),
            const SizedBox(height: Space.xs),
            Text('listened $periodPhrase', style: t.body.copyWith(color: t.textSecondary)),
            const SizedBox(height: Space.xxl),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Figure(
                      first: true,
                      value: _Counting(target: stats.totalPlays, format: compactCount, style: figureStyle(t, 24)),
                      label: stats.totalPlays == 1 ? 'play' : 'plays',
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Figure(
                      value: Text('$skip%', style: figureStyle(t, 24).copyWith(color: skipColor)),
                      label: 'skipped',
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Figure(
                      value: Text('${stats.streakDays}', style: figureStyle(t, 24)),
                      label: 'day streak',
                    ),
                  ),
                ],
              ),
            ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: Space.xxl),
              _Fortnight(days: days),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final Widget value;
  final String label;

  /// The first figure hangs on the page margin.
  final bool first;
  const _Figure({required this.value, required this.label, this.first = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(left: first ? 0 : Space.md, right: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        ],
      ),
    );
  }
}

/// Hairline between the supporting figures; the first figure hangs on the
/// page margin, so dividers carry the rhythm instead of boxes.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(width: 0.5, color: ThemeTokens.of(context).outline);
}

/// A number that counts up once when it first appears (skipped when the
/// system asks for reduced motion).
class _Counting extends StatelessWidget {
  final int target;
  final String Function(int) format;
  final TextStyle style;
  const _Counting({required this.target, required this.format, required this.style});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return Text(format(target), style: style);
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: target),
      duration: Motion.slow * 3,
      curve: Curves.easeOutExpo,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

/// The last 14 days as bars sized by plays, today on the right and lit;
/// a day without music stays a short stub so gaps in a streak read at once.
class _Fortnight extends StatelessWidget {
  static const _window = 14;
  static const _height = 44.0;
  final List<ContributionDay> days;
  const _Fortnight({required this.days});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final byDate = {for (final d in days) d.date: d.count};
    final now = DateTime.now();
    final counts = [
      for (var i = 0; i < _window; i++) byDate[isoDate(now.subtract(Duration(days: _window - 1 - i)))] ?? 0,
    ];
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Last 2 weeks', style: t.footnote),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _window; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: max == 0 || counts[i] == 0 ? 4 : 8 + (_height - 8) * counts[i] / max,
                    decoration: BoxDecoration(
                      color: counts[i] == 0 ? t.fill : (i == _window - 1 ? t.accent : t.accentDim),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.xs + 2),
        Row(
          children: [
            for (var i = 0; i < _window; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  weekdays[now.subtract(Duration(days: _window - 1 - i)).weekday - 1],
                  textAlign: TextAlign.center,
                  style: t.caption2.copyWith(color: i == _window - 1 ? t.textPrimary : t.textMuted),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
