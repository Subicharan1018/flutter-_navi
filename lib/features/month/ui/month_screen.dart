import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/controls.dart' show FilterPills;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import '../../listen/ui/pick_row.dart';
import '../logic/month_providers.dart';

const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Your month: minutes, streak, what you played most and what you found.
class MonthScreen extends ConsumerWidget {
  const MonthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(selectedMonthProvider);
    final async = ref.watch(monthStatsProvider(picked));
    final stats = async.asData?.value;
    return LargeTitlePage(
      title: 'Your Month',
      clearPlayer: false,
      onRefresh: () => ref.refresh(monthStatsProvider(picked).future),
      header: stats == null || stats.months.length < 2
          ? null
          : FilterPills<MonthKey>(
              options: {for (final m in stats.months.take(12)) m: '${_short[m.month - 1]} ${m.year}'},
              value: MonthKey(stats.year, stats.month),
              onChanged: ref.read(selectedMonthProvider.notifier).select,
            ),
      headerPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      slivers: [
        if (stats != null && !stats.isEmpty)
          SliverToBoxAdapter(child: MonthBody(stats: stats))
        else
          SliverToBoxAdapter(
            child: async.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: Space.sm), child: TrackListSkeleton(rows: 6)),
              error: (e, _) => MessageState.error(
                title: 'Your month didn’t load',
                message: '$e',
                onRetry: () => ref.invalidate(monthStatsProvider(picked)),
              ),
              data: (_) => const MessageState(
                art: EmptyArtKind.signal,
                title: 'Nothing played this month',
                message: 'Play some music and your top songs, artists and minutes show up here.',
              ),
            ),
          ),
      ],
    );
  }
}

/// The month's numbers and lists.
class MonthBody extends ConsumerWidget {
  final MonthStats stats;
  const MonthBody({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final change = minutesChange(stats.totalMinutes, stats.previousMinutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${stats.monthName} ${stats.year}', style: t.footnote),
              Text(minutesLabel(stats.totalMinutes), style: t.largeTitle.copyWith(fontSize: 56, height: 1.1)),
              Text(change == null ? 'listened' : 'listened · $change', style: t.subheadline),
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  _Stat(glyph: NaviGlyph.play, value: '${stats.totalPlays}', label: 'plays'),
                  _Stat(glyph: NaviGlyph.calendar, value: '${stats.activeDays}/${stats.daysInMonth}', label: 'days'),
                  _Stat(glyph: NaviGlyph.flame, value: '${stats.streakDays}', label: 'day streak'),
                  _Stat(glyph: NaviGlyph.note, value: '${stats.newSongsCount}', label: 'new songs'),
                ],
              ),
              const SizedBox(height: Space.xl),
              SizedBox(height: 56, child: CustomPaint(painter: DailyBars(stats.dailyMinutes, t.accent, t.fill), size: Size.infinite)),
            ],
          ),
        ),
        if (stats.topSongs.isNotEmpty) ...[
          const SectionHeader(title: 'Top Songs'),
          for (var i = 0; i < stats.topSongs.length; i++)
            PickRow(
              songId: stats.topSongs[i].songId,
              title: stats.topSongs[i].title,
              artist: stats.topSongs[i].artist,
              tag: '${i + 1}',
              why: '${stats.topSongs[i].plays} plays · ${minutesLabel(stats.topSongs[i].minutes)}',
              showSeparator: i < stats.topSongs.length - 1,
              onTap: () => _play(context, ref, [for (final s in stats.topSongs) s.songId], i),
            ),
        ],
        _People(title: 'Top Artists', people: stats.topArtists),
        _People(title: 'Top Composers', people: stats.topComposers),
        if (stats.newSongs.isNotEmpty) ...[
          SectionHeader(title: 'Found This Month · ${stats.newSongsCount}'),
          for (var i = 0; i < stats.newSongs.length; i++)
            PickRow(
              songId: stats.newSongs[i].songId,
              title: stats.newSongs[i].title,
              artist: stats.newSongs[i].artist,
              why: '${stats.newSongs[i].plays} plays so far',
              showSeparator: i < stats.newSongs.length - 1,
              onTap: () => _play(context, ref, [for (final s in stats.newSongs) s.songId], i),
            ),
        ],
      ],
    );
  }
}

Future<void> _play(BuildContext context, WidgetRef ref, List<String> ids, int from) async {
  final songs = await ref.read(listenSongsProvider).load(ids);
  if (songs.isEmpty) return;
  final start = songs.indexWhere((s) => s.id == ids[from]);
  await ref.read(playerProvider.notifier).setQueue(songs, start < 0 ? 0 : start, playlistName: 'Your Month');
}

class _Stat extends StatelessWidget {
  final NaviGlyph glyph;
  final String value;
  final String label;
  const _Stat({required this.glyph, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NaviIcon(glyph, size: 18, color: t.textSecondary),
          const SizedBox(height: Space.xs),
          Text(value, style: t.title2),
          Text(label, style: t.footnote),
        ],
      ),
    );
  }
}

/// Artists or composers as round covers (a generated cover when no song cover is known).
class _People extends ConsumerWidget {
  final String title;
  final List<MonthPerson> people;
  const _People({required this.title, required this.people});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (people.isEmpty) return const SizedBox.shrink();
    const size = 112.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: size + 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final p = people[i];
              final art = p.artId == null ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(p.artId);
              return MediaCard(
                title: p.name,
                subtitle: '${p.plays} plays · ${minutesLabel(p.minutes)}',
                artUrl: art,
                art: art != null
                    ? null
                    : ClipOval(child: SizedBox.square(dimension: size, child: GeneratedCover(name: p.name))),
                size: size,
                circular: true,
                onTap: () {},
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One bar per day of the month, as tall as that day's minutes.
class DailyBars extends CustomPainter {
  final List<int> minutes;
  final Color ink;
  final Color empty;
  const DailyBars(this.minutes, this.ink, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    if (minutes.isEmpty) return;
    final peak = minutes.reduce((a, b) => a > b ? a : b);
    final slot = size.width / minutes.length;
    final w = (slot * 0.62).clamp(1.0, 8.0);
    for (var i = 0; i < minutes.length; i++) {
      final h = peak == 0 || minutes[i] == 0 ? 3.0 : (minutes[i] / peak * size.height).clamp(3.0, size.height);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - w) / 2, size.height - h, w, h),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(r, Paint()..color = minutes[i] == 0 ? empty : ink);
    }
  }

  @override
  bool shouldRepaint(DailyBars old) => old.minutes != minutes || old.ink != ink || old.empty != empty;
}
