import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/motion/number_roll.dart';
import 'glass_sheet.dart';
import 'listener_type.dart';
import 'ring_gauge.dart';
import 'sparkline.dart';
import 'stat_card.dart';
import 'stat_tile.dart';
import 'streak_ticket.dart';

/// The top of Stats: a frosted sheet over the top artist's own picture, with
/// who you are as a listener, time listened as one huge rolling figure, the
/// shape of the period as a line, and plays and skip rate beneath. The streak
/// follows as its own ticket.
class SummaryHero extends StatelessWidget {
  final ListeningStatsResponse stats;

  /// "in the last 7 days", "all time"…
  final String periodPhrase;

  /// Plays per day, oldest first; drawn as a sparkline when there are enough.
  final List<double> dailyPlays;

  /// The artist with the most plays in the period, if any.
  final String? topArtist;

  /// That artist's picture; it is what the sheet is frosted over.
  final String? topArtistCover;

  const SummaryHero({
    super.key,
    required this.stats,
    required this.periodPhrase,
    this.dailyPlays = const [],
    this.topArtist,
    this.topArtistCover,
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
            GlassSheet(
              coverUrl: topArtistCover,
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
                      style: figureStyle(t, 76).copyWith(color: t.accent, letterSpacing: -3, height: 0.95),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text('listened $periodPhrase', style: t.title3.copyWith(color: t.textSecondary, fontWeight: FontWeight.w500)),
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
                  if (dailyPlays.length > 2) ...[
                    const SizedBox(height: Space.xl),
                    Sparkline(values: dailyPlays, height: 72),
                  ],
                  const SizedBox(height: Space.xl),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: StatTile(
                            glyph: NaviGlyph.play,
                            value: NumberRoll(value: stats.totalPlays, format: compactCount, style: figureStyle(t, 24)),
                            label: stats.totalPlays == 1 ? 'play' : 'plays',
                          ),
                        ),
                        Container(width: 0.5, color: t.outline),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: Space.lg),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            StreakTicket(streak: stats.streakDays),
          ],
        ),
      ),
    );
  }
}
