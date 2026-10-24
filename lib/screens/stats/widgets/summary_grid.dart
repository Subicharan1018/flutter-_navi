import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/motion/number_roll.dart';
import 'ring_gauge.dart';
import 'sparkline.dart';
import 'stat_card.dart';
import 'stat_tile.dart';

/// The top of Stats: time listened as one big rolling figure, the way Apple
/// Fitness leads with the number you care about. Plays, skip rate and streak
/// sit under it as supporting figures, with a sparkline of recent plays.
class SummaryHero extends StatelessWidget {
  final ListeningStatsResponse stats;

  /// "in the last 7 days", "all time"…
  final String periodPhrase;

  /// Plays per day, oldest first; drawn as a sparkline when there are enough.
  final List<double> dailyPlays;

  const SummaryHero({super.key, required this.stats, required this.periodPhrase, this.dailyPlays = const []});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final skip = (stats.skipRate * 100).round().clamp(0, 100);
    // Only a skip rate that says something's off is worth colouring.
    final skipColor = skip > 30 ? t.danger : t.accent;

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
              child: NumberRoll(
                value: stats.totalMinutes,
                format: listeningTime,
                style: figureStyle(t, 64).copyWith(color: t.accent, letterSpacing: -2.4),
              ),
            ),
            const SizedBox(height: Space.xs),
            Text('listened $periodPhrase', style: t.body.copyWith(color: t.textSecondary)),
            if (dailyPlays.length > 2) ...[
              const SizedBox(height: Space.lg),
              Sparkline(values: dailyPlays, height: 44),
            ],
            const SizedBox(height: Space.xxl),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Cell(
                      first: true,
                      child: StatTile(
                        glyph: NaviGlyph.play,
                        value: NumberRoll(value: stats.totalPlays, format: compactCount, style: figureStyle(t, 24)),
                        label: stats.totalPlays == 1 ? 'play' : 'plays',
                      ),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Cell(
                      child: StatTile(
                        value: RingGauge(
                          value: stats.skipRate,
                          size: 44,
                          stroke: 4,
                          color: skipColor,
                          center: Text('$skip%', style: figureStyle(t, 12).copyWith(color: skipColor)),
                        ),
                        label: 'skipped',
                      ),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Cell(
                      child: StatTile(
                        glyph: NaviGlyph.flame,
                        value: NumberRoll(value: stats.streakDays, style: figureStyle(t, 24)),
                        label: 'day streak',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final Widget child;

  /// The first figure hangs on the page margin.
  final bool first;
  const _Cell({required this.child, this.first = false});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: first ? 0 : Space.md, right: Space.md), child: child);
}

/// Hairline between the supporting figures; the first figure hangs on the
/// page margin, so dividers carry the rhythm instead of boxes.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(width: 0.5, color: ThemeTokens.of(context).outline);
}
