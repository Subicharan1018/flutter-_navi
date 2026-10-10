import 'package:flutter/cupertino.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../../features/ai_shuffle/data/models/listening_stats_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// The four period totals as tiles, Apple Fitness style: what you did, in
/// big numbers, each with the one shape that explains it.
class SummaryGrid extends StatelessWidget {
  final ListeningStatsResponse stats;
  final List<ContributionDay> days;
  const SummaryGrid({super.key, required this.stats, required this.days});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final skip = (stats.skipRate * 100).round().clamp(0, 100);
    final skipColor = skip > 20 ? t.danger : (skip >= 10 ? t.warning : t.positive);

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 640 ? 4 : 2;
      final width = (c.maxWidth - Space.md * (columns - 1)) / columns;
      final tiles = [
        _Tile(
          label: 'Plays',
          icon: CupertinoIcons.play_fill,
          value: _Counting(target: stats.totalPlays, format: compactCount),
        ),
        _Tile(
          label: 'Listening Time',
          icon: CupertinoIcons.time,
          value: _Counting(target: stats.totalMinutes, format: listeningTime),
        ),
        _Tile(
          label: 'Skipped',
          icon: CupertinoIcons.forward_end_fill,
          iconColor: skipColor,
          value: Text('$skip%', style: figureStyle(t, 30).copyWith(color: skipColor)),
          footer: _Proportion(played: 100 - skip, color: skipColor),
        ),
        _Tile(
          label: 'Streak',
          icon: CupertinoIcons.flame_fill,
          iconColor: stats.streakDays > 0 ? t.warning : t.textMuted,
          value: Text(
            stats.streakDays == 1 ? '1 day' : '${stats.streakDays} days',
            style: figureStyle(t, 30),
          ),
          footer: _Fortnight(days: days, live: stats.streakDays > 0 ? t.warning : t.textMuted),
        ),
      ];
      return Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Widget value;
  final Widget? footer;

  const _Tile({required this.label, required this.icon, this.iconColor, required this.value, this.footer});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      height: 128,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.group)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor ?? t.accent),
              const SizedBox(width: Space.xs + 2),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline)),
            ],
          ),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          if (footer != null) ...[const SizedBox(height: Space.sm), footer!],
        ],
      ),
    );
  }
}

/// A number that counts up once when it first appears (skipped when the
/// system asks for reduced motion).
class _Counting extends StatelessWidget {
  final int target;
  final String Function(int) format;
  const _Counting({required this.target, required this.format});

  @override
  Widget build(BuildContext context) {
    final style = figureStyle(ThemeTokens.of(context), 30);
    if (MediaQuery.disableAnimationsOf(context)) return Text(format(target), style: style);
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: target),
      duration: Motion.slow * 2,
      curve: Motion.ease,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

/// Played-through vs skipped as one split bar.
class _Proportion extends StatelessWidget {
  final int played;
  final Color color;
  const _Proportion({required this.played, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: played.clamp(1, 100), child: ColoredBox(color: t.fill)),
            if (played < 100) ...[
              const SizedBox(width: 2),
              Expanded(flex: 100 - played, child: ColoredBox(color: color)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The last 14 days, one tick each, lit on days you listened.
class _Fortnight extends StatelessWidget {
  static const _window = 14;
  final List<ContributionDay> days;
  final Color live;
  const _Fortnight({required this.days, required this.live});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final byDate = {for (final d in days) d.date: d.count};
    final now = DateTime.now();
    return SizedBox(
      height: 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _window; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: (byDate[isoDate(now.subtract(Duration(days: _window - 1 - i)))] ?? 0) > 0 ? live : t.fill,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
