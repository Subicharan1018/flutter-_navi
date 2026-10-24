import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../screens/stats/widgets/heat_grid.dart';
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/motion/number_roll.dart';
import '../../../../widgets/motion/play_once.dart';
import '../../../listen/data/listen_models.dart';
import '../../logic/month_providers.dart';

// Story cards are always white on black, like the share card, so they read
// the same in every theme. Every card takes the pager's clock `p` (0..1) and
// staggers its parts with [sliceOf]; nothing here owns a controller.
const _ink = Color(0xFFFFFFFF);
const _dim = Color(0xFF9E9EA4);
const _track = Color(0xFF2C2C2E);

/// Fades and lifts [child] into place between [begin] and [end] of the card's clock.
class StoryIn extends StatelessWidget {
  final Animation<double> p;
  final double begin;
  final double end;
  final Widget child;
  const StoryIn({super.key, required this.p, required this.begin, required this.end, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: p,
        child: child,
        builder: (context, child) {
          final k = sliceOf(p.value, begin, end);
          if (k >= 1) return child!;
          return Opacity(opacity: k, child: Transform.translate(offset: Offset(0, 24 * (1 - k)), child: child));
        },
      );
}

/// Common layout: a small kicker and headline, then the card's picture.
class StoryFrame extends StatelessWidget {
  final Animation<double> p;
  final String kicker;
  final String? headline;
  final Widget child;
  const StoryFrame({super.key, required this.p, required this.kicker, this.headline, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xxl, MediaQuery.paddingOf(context).top + 64, Space.xxl, MediaQuery.paddingOf(context).bottom + Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoryIn(
            p: p,
            begin: 0,
            end: 0.12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kicker, style: t.callout.copyWith(color: _dim)),
                if (headline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(headline!, style: t.textStyle(30, FontWeight.w700, _ink).copyWith(height: 1.12, letterSpacing: -0.8)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 1. Minutes: the number rolls up like an odometer.
class MinutesCard extends StatelessWidget {
  final MonthStats stats;
  final Animation<double> p;
  const MinutesCard({super.key, required this.stats, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final change = minutesChange(stats.totalMinutes, stats.previousMinutes);
    return StoryFrame(
      p: p,
      kicker: '${stats.monthName} ${stats.year}',
      headline: 'You listened for',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumberRoll(
              value: stats.totalMinutes,
              format: minutesLabel,
              progress: p,
              window: 0.45,
              style: t.textStyle(88, FontWeight.w800, _ink).copyWith(
                    height: 1.05,
                    letterSpacing: -4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          const SizedBox(height: Space.md),
          StoryIn(
            p: p,
            begin: 0.45,
            end: 0.65,
            child: Text(
              '${stats.totalPlays} plays · ${stats.uniqueSongs} different songs${change == null ? '' : '\n$change'}',
              style: t.body.copyWith(color: _dim, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. Top song: its cover with rings pulsing out from behind.
class TopSongCard extends ConsumerWidget {
  final MonthSong song;
  final Animation<double> p;
  const TopSongCard({super.key, required this.song, required this.p});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.songId, size: 600);
    return StoryFrame(
      p: p,
      kicker: 'Your song of the month',
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: p,
                        builder: (context, _) => CustomPaint(painter: PulseRingsPainter(p.value)),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.66,
                      heightFactor: 0.66,
                      child: StoryIn(p: p, begin: 0, end: 0.2, child: StoryCover(url: url, name: song.title)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          StoryIn(
            p: p,
            begin: 0.2,
            end: 0.4,
            child: Column(
              children: [
                Text(song.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textStyle(26, FontWeight.w700, _ink)),
                const SizedBox(height: Space.xs),
                Text(song.artist, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(color: _dim)),
                const SizedBox(height: Space.md),
                Text('${song.plays} plays · ${minutesLabel(song.minutes)}', style: t.subheadline.copyWith(color: _dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A generated cover with the real one fading in over it when it loads, so a
/// song without art (or offline) still gets a handsome square.
class StoryCover extends StatelessWidget {
  final String? url;
  final String name;
  const StoryCover({super.key, required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final px = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 0.66).round();
    const clear = SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.cover + 4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GeneratedCover(name: name),
          if (url != null)
            CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: px,
              fadeInDuration: Motion.standard,
              placeholder: (_, _) => clear,
              errorWidget: (_, _, _) => clear,
            ),
        ],
      ),
    );
  }
}

/// Three rings that swell and fade out of the cover, staggered a third of a
/// beat apart. [t] is the card's clock; it makes [cycles] full pulses.
class PulseRingsPainter extends CustomPainter {
  static const cycles = 7;
  final double t;
  const PulseRingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width * 0.33;
    for (var k = 0; k < 3; k++) {
      final phase = (t * cycles + k / 3) % 1;
      final r = base * (1 + 0.55 * phase);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _ink.withValues(alpha: 0.45 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(PulseRingsPainter old) => old.t != t;
}

/// 3 & 4. Top artists / composers as bars rising one after another.
class PeopleCard extends StatelessWidget {
  final String kicker;
  final String headline;
  final List<MonthPerson> people;
  final Animation<double> p;
  const PeopleCard({super.key, required this.kicker, required this.headline, required this.people, required this.p});

  @override
  Widget build(BuildContext context) {
    final top = people.take(5).toList();
    final peak = top.fold<int>(0, (m, e) => e.minutes > m ? e.minutes : m);
    return StoryFrame(
      p: p,
      kicker: kicker,
      headline: headline,
      child: AnimatedBuilder(
        animation: p,
        builder: (context, _) => _RisingBars(
          people: top,
          share: [for (final e in top) peak == 0 ? 0.0 : e.minutes / peak],
          t: p.value,
        ),
      ),
    );
  }
}

class _RisingBars extends StatelessWidget {
  final List<MonthPerson> people;
  final List<double> share;
  final double t;
  const _RisingBars({required this.people, required this.share, required this.t});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeTokens.of(context);
    final n = people.length;
    return LayoutBuilder(
      builder: (context, c) {
        const label = 64.0;
        final room = math.max(40.0, c.maxHeight - label);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, person) in people.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // The bar rises from the floor; the first place leads and is brightest.
                      Container(
                        height: math.max(6.0, room * share[i] * sliceOf(t, 0.08 + i * 0.1, 0.4 + i * 0.1, Curves.easeOutBack).clamp(0.0, 1.05)),
                        decoration: BoxDecoration(
                          color: i == 0 ? _ink : Color.lerp(_ink, _track, 0.45 + 0.1 * i),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        height: label - Space.sm,
                        child: Opacity(
                          opacity: sliceOf(t, 0.3 + i * 0.1, 0.45 + i * 0.1),
                          child: Column(
                            children: [
                              Text('${i + 1}', style: theme.footnote.copyWith(color: _dim)),
                              Text(
                                person.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: theme.caption1.copyWith(color: _ink, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (n == 0) const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

/// 5. The month as a strip of days that fills in day by day.
class CalendarCard extends StatelessWidget {
  final MonthStats stats;
  final Animation<double> p;
  const CalendarCard({super.key, required this.stats, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final peak = stats.dailyMinutes.fold<int>(0, (m, v) => v > m ? v : m);
    final best = peak == 0 ? 0 : stats.dailyMinutes.indexOf(peak) + 1;
    return StoryFrame(
      p: p,
      kicker: 'Day by day',
      headline: '${stats.activeDays} of ${stats.daysInMonth} days with music',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Days fill in order across the card's clock.
          HeatGrid(
            values: [for (final m in stats.dailyMinutes) peak == 0 ? 0 : m / peak],
            rows: 5,
            gap: 6,
            radius: 6,
            color: _ink,
            emptyColor: _track,
            progress: _Window(p, 0.1, 0.75),
            semanticLabel: '${stats.activeDays} of ${stats.daysInMonth} days with music',
          ),
          const SizedBox(height: Space.xl),
          if (best > 0)
            StoryIn(
              p: p,
              begin: 0.75,
              end: 0.95,
              child: Text(
                'Your biggest day was the $best${_ordinal(best)}: ${minutesLabel(peak)}.',
                style: t.body.copyWith(color: _dim),
              ),
            ),
        ],
      ),
    );
  }

  static String _ordinal(int d) =>
      d % 100 >= 11 && d % 100 <= 13 ? 'th' : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

/// 6. Streak: one square per day, filling in one by one.
class StreakCard extends StatelessWidget {
  final MonthStats stats;
  final Animation<double> p;
  const StreakCard({super.key, required this.stats, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final days = stats.streakDays.clamp(0, stats.daysInMonth);
    return StoryFrame(
      p: p,
      kicker: 'Your longest streak',
      headline: days == 1 ? '1 day in a row' : '$days days in a row',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MICRODUCK: the line-art duck mascot goes here, walking along the
          // streak. Place `MicroduckStrip(progress: _Window(p, 0.1, 0.8))`
          // (lib/widgets/mascot/) in this slot; its progress matches the
          // squares below so the duck reaches the last square as it fills.
          const SizedBox(height: 56, key: ValueKey('microduck-slot')),
          const SizedBox(height: Space.lg),
          if (days > 0)
            HeatGrid(
              values: List.filled(days, 1.0),
              rows: (days / 8).ceil(),
              rowMajor: true,
              cell: 28,
              gap: 8,
              radius: 7,
              color: _ink,
              emptyColor: _track,
              progress: _Window(p, 0.1, 0.8),
              semanticLabel: '$days day streak',
            ),
          const SizedBox(height: Space.xl),
          StoryIn(
            p: p,
            begin: 0.8,
            end: 0.95,
            child: Row(
              children: [
                const NaviIcon(NaviGlyph.flame, size: 18, color: _dim),
                const SizedBox(width: Space.sm),
                Text('Keep it going next month.', style: t.body.copyWith(color: _dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [parent] stretched so that [begin]..[end] of it plays as 0..1, without a
/// controller: a view onto the card's clock for a primitive that wants its own 0..1.
class _Window extends Animation<double> with AnimationWithParentMixin<double> {
  @override
  final Animation<double> parent;
  final double begin;
  final double end;
  const _Window(this.parent, this.begin, this.end);

  @override
  double get value => ((parent.value - begin) / (end - begin)).clamp(0.0, 1.0);
}
