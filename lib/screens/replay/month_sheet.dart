import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/listen/data/listen_models.dart' show MonthKey;
import '../../features/month/ui/story/month_story.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../widgets/art/navi_icons.dart';
import '../../utils/format.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../stats/widgets/stat_card.dart';
import 'replay_rows.dart';

/// One month of Replay in a sheet: the month's numbers, a bar per day, its
/// top songs and artists, and the last things you played.
class MonthSheet extends ConsumerWidget {
  final int year;
  final int month;
  const MonthSheet({super.key, required this.year, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (year: year, month: month);
    final data = ref.watch(navivibeMonthlyReplayProvider(key));
    return data.when(
      loading: () => const LoadingState(),
      error: (_, _) => MessageState.error(
        title: 'Couldn’t load this month',
        onRetry: () => ref.invalidate(navivibeMonthlyReplayProvider(key)),
      ),
      data: (m) => _Content(month: m),
    );
  }
}

class _Content extends StatelessWidget {
  final MonthlyReplayResponse month;
  const _Content({required this.month});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final figures = [
      (listeningTime(month.totalMinutes.round()), 'listened'),
      (compactCount(month.totalPlays), 'plays'),
      ('${month.listeningDays}', 'days'),
      (month.streakDays == 1 ? '1 day' : '${month.streakDays} days', 'best streak'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Row(
            children: [
              Expanded(child: Text('${month.monthName} ${month.year}', style: t.title1)),
              CupertinoClickable(
                onTap: () => showMonthStory(context, month: MonthKey(month.year, month.month)),
                semanticLabel: 'Play ${month.monthName} story',
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(17)),
                  child: Row(
                    children: [
                      NaviIcon(NaviGlyph.play, size: 12, color: t.onAccent, filled: true),
                      const SizedBox(width: 6),
                      Text('Story', style: t.subheadline.copyWith(color: t.onAccent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              for (final (value, label) in figures)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: figureStyle(t, 20))),
                      Text(label, style: t.caption1),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (month.dailyBreakdown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
            child: _Days(days: month.dailyBreakdown),
          ),
        if (month.topTracks.isNotEmpty) ...[
          const SectionHeader(title: 'Top Songs'),
          for (final (i, track) in month.topTracks.take(5).indexed) ReplayTrackRow(track: track, rank: i + 1),
        ],
        if (month.topArtists.isNotEmpty)
          MediaShelf(
            title: 'Top Artists',
            cardSize: 104,
            itemCount: month.topArtists.length.clamp(0, 8),
            itemBuilder: (context, i) => ReplayArtistCard(artist: month.topArtists[i], size: 104),
          ),
        if (month.recentPlays.isNotEmpty) ...[
          const SectionHeader(title: 'Last Played'),
          for (final p in month.recentPlays.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                        Text(p.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                      ],
                    ),
                  ),
                  Text(_when(p.playedAtIst), style: t.footnote),
                ],
              ),
            ),
        ],
        const SizedBox(height: Space.xl),
      ],
    );
  }

  /// "Oct 4, 9:41 pm" from the server's ISO timestamp.
  static String _when(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final minute = d.minute.toString().padLeft(2, '0');
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${months[d.month - 1]} ${d.day}, $h:$minute ${d.hour < 12 ? 'am' : 'pm'}';
  }
}

/// One bar per day of the month, height = plays.
class _Days extends StatelessWidget {
  final List<ReplayDailyEntry> days;
  const _Days({required this.days});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final max = days.fold<int>(0, (m, d) => d.playCount > m ? d.playCount : m);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Container(
                height: 3 + 53 * (max == 0 ? 0 : d.playCount / max),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: d.playCount == 0 ? t.fill : t.accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
