import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/motion/number_roll.dart';
import 'ring_gauge.dart';
import 'sparkline.dart';
import 'listener_type.dart';
import 'streak_dots.dart';
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

  /// The artist with the most plays in the period, if any.
  final String? topArtist;

  const SummaryHero({
    super.key,
    required this.stats,
    required this.periodPhrase,
    this.dailyPlays = const [],
    this.topArtist,
  });

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
            ListenerTypeLine(byHour: stats.hourlyHeatmap),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: NumberRoll(
                value: stats.totalMinutes,
                format: listeningTime,
                style: figureStyle(t, 88).copyWith(color: t.accent, letterSpacing: -3.6, height: 0.95),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text('listened $periodPhrase', style: t.title3.copyWith(color: t.textSecondary, fontWeight: FontWeight.w500)),
            // One line of character: who the time went to.
            if (topArtist != null && topArtist!.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Mostly ', style: t.body.copyWith(color: t.textMuted)),
                  TextSpan(text: topArtist, style: t.body.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // The hero visual: the shape of the period, drawn tall.
            if (dailyPlays.length > 2) ...[
              const SizedBox(height: Space.xl),
              Sparkline(values: dailyPlays, height: 96, color: t.gold),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NaviIcon(NaviGlyph.flame, size: 18, color: t.gold),
                          const SizedBox(height: Space.xs),
                          NumberRoll(value: stats.streakDays, style: figureStyle(t, 24)),
                          const SizedBox(height: Space.xs),
                          StreakDots(streak: stats.streakDays),
                          const SizedBox(height: Space.xs),
                          Text('day streak', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                        ],
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
