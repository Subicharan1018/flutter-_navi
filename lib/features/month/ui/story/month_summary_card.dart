import 'package:flutter/widgets.dart';

import '../../../../core/theme.dart';
import '../../../../screens/stats/widgets/heat_grid.dart';
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../listen/data/listen_models.dart';
import '../../logic/month_providers.dart';

/// The picture sent from the end of a month story. Like the song share card
/// it is always white on black so it reads the same on the friend's screen,
/// whatever theme the app is in. Drawn finished (no animation) because it is
/// captured to a PNG.
class MonthSummaryCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 450;

  final MonthStats stats;
  const MonthSummaryCard({super.key, required this.stats});

  static const _ground = Color(0xFF000000);
  static const _label = Color(0xFFFFFFFF);
  static const _secondary = Color(0xFF9E9EA4);
  static const _empty = Color(0xFF2C2C2E);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final peak = stats.dailyMinutes.fold<int>(0, (m, v) => v > m ? v : m);
    final song = stats.topSongs.firstOrNull;
    final artist = stats.topArtists.firstOrNull;
    return Container(
      width: width,
      height: height,
      color: _ground,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${stats.monthName} ${stats.year}', style: t.callout.copyWith(color: _secondary)),
          const SizedBox(height: 2),
          Text(minutesLabel(stats.totalMinutes), style: t.textStyle(56, FontWeight.w700, _label).copyWith(height: 1.05, letterSpacing: -2)),
          Text('listened', style: t.callout.copyWith(color: _secondary)),
          const SizedBox(height: Space.xl),
          if (song != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.cover),
                  child: SizedBox.square(dimension: 64, child: GeneratedCover(name: song.title)),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top song', style: t.caption1.copyWith(color: _secondary)),
                      Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headline.copyWith(color: _label)),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: _secondary)),
                    ],
                  ),
                ),
              ],
            ),
          if (artist != null) ...[
            const SizedBox(height: Space.lg),
            Text('Top artist', style: t.caption1.copyWith(color: _secondary)),
            Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.title3.copyWith(color: _label)),
          ],
          const Spacer(),
          HeatGrid(
            values: [for (final m in stats.dailyMinutes) peak == 0 ? 0 : m / peak],
            color: _label,
            emptyColor: _empty,
            progress: const AlwaysStoppedAnimation(1),
            gap: 2,
            radius: 2,
          ),
          const SizedBox(height: Space.sm),
          Text(
            '${stats.activeDays} of ${stats.daysInMonth} days · ${stats.streakDays} day streak',
            style: t.caption1.copyWith(color: _secondary),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              const NaviIcon(NaviGlyph.note, size: 13, color: _secondary),
              const SizedBox(width: 6),
              Text('My month on NaviVibe', style: t.caption1.copyWith(color: _secondary)),
            ],
          ),
        ],
      ),
    );
  }
}
