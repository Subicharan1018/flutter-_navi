import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/ai_shuffle/logic/recommendation_resolver.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/ui/artwork_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/mosaic_art.dart';
import '../../widgets/ui/states.dart';
import '../stats/widgets/genre_mix.dart';
import '../stats/widgets/hours_chart.dart';
import '../stats/widgets/stat_card.dart';
import 'month_sheet.dart';
import 'replay_rows.dart';

/// Replay, the way Apple Music does it: your year as a playlist. The hero is
/// a mosaic of your top songs' covers, Play plays them, and below sit the
/// numbers, your top songs and artists, and the year month by month.
class ReplayScreen extends ConsumerStatefulWidget {
  const ReplayScreen({super.key});

  @override
  ConsumerState<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends ConsumerState<ReplayScreen> {
  /// Null = the server's current year.
  int? _year;

  /// Top songs that exist in the local library, in rank order.
  List<Song> _playable(YearlyReplayResponse r) {
    final library = ref.read(allSongsProvider).asData?.value ?? const <Song>[];
    final matcher = RecommendationResolver(library);
    return [for (final t in r.topTracks) ?matcher.match(t.title, t.artist)];
  }

  Future<void> _play(YearlyReplayResponse r, {bool shuffle = false, int from = 0}) async {
    final songs = _playable(r);
    if (songs.isEmpty) {
      showToast(context, 'Your top songs aren’t in the library on this device yet.');
      return;
    }
    final n = ref.read(playerProvider.notifier);
    final name = 'Replay ${r.year}';
    shuffle
        ? await n.playPlaylist(songs, shuffle: true, playlistName: name)
        : await n.setQueue(songs, from.clamp(0, songs.length - 1), playlistName: name, unshuffledSongs: songs);
  }

  Future<void> _pickYear(YearlyReplayResponse r) async {
    final year = await showChoiceSheet<int>(
      context,
      title: 'Replay Year',
      options: r.availableYears,
      selected: r.year,
      label: (y) => '$y',
    );
    if (year != null && mounted) setState(() => _year = year);
  }

  @override
  Widget build(BuildContext context) {
    final replay = ref.watch(navivibeYearlyReplayProvider(_year));
    ref.watch(allSongsProvider); // keeps top songs playable as the mirror fills
    final r = replay.asData?.value;
    final year = r?.year ?? _year ?? DateTime.now().year;
    final tracks = r?.topTracks ?? const <ReplayTrack>[];
    final coverIds = [
      for (final t in tracks.take(8)) ref.watch(songCoverIdProvider('${t.title}|${t.artist}')).asData?.value,
    ];
    final svc = ref.read(subsonicServiceProvider);

    return ArtworkPage(
      paletteCoverId: coverIds.nonNulls.firstOrNull,
      art: (size) => MosaicArt(
        urls: [for (final id in coverIds) id == null ? null : svc.getCoverArtUrl(id)],
        size: size,
        radius: 0,
        placeholderIcon: CupertinoIcons.calendar,
        seed: coverSeed('Replay $year'),
      ),
      title: 'Replay $year',
      subtitle: r == null || r.totalPlays == 0 ? null : '${_comma(r.totalMinutes.round())} minutes',
      detail: r == null || r.totalPlays == 0
          ? null
          : '${songCount(r.uniqueSongs)} · ${r.uniqueArtists} artists · ${r.listeningDays} days',
      buttons: r == null
          ? null
          : PlayShuffleButtons(
              onPlay: tracks.isEmpty ? null : () => _play(r),
              onShuffle: tracks.isEmpty ? null : () => _play(r, shuffle: true),
              trailing: r.availableYears.length > 1
                  ? CircleIconButton(icon: CupertinoIcons.calendar, label: 'Choose year', onTap: () => _pickYear(r))
                  : null,
            ),
      onRefresh: () async => ref.invalidate(navivibeYearlyReplayProvider(_year)),
      slivers: replay.when(
        loading: () => const [SliverToBoxAdapter(child: LoadingState())],
        error: (_, _) => [
          SliverToBoxAdapter(
            child: MessageState.error(
              title: 'Replay isn’t available',
              message: 'Replay comes from your Smart Shuffle server. Check that it’s running, then try again.',
              onRetry: () => ref.invalidate(navivibeYearlyReplayProvider(_year)),
            ),
          ),
        ],
        data: (r) => r.totalPlays == 0
            ? [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: CupertinoIcons.calendar,
                    title: 'Your Replay starts with your first song',
                    message: 'Listen this year and your top songs, artists and months collect here.',
                  ),
                ),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  sliver: SliverToBoxAdapter(child: _Figures(replay: r)),
                ),
                if (tracks.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Top Songs')),
                  SliverList.builder(
                    itemCount: tracks.length.clamp(0, 10),
                    itemBuilder: (context, i) => ReplayTrackRow(
                      track: tracks[i],
                      rank: i + 1,
                      onTap: () => _play(r, from: i),
                    ),
                  ),
                ],
                if (r.topArtists.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MediaShelf(
                      title: 'Top Artists',
                      cardSize: 120,
                      itemCount: r.topArtists.length.clamp(0, 10),
                      itemBuilder: (context, i) => ReplayArtistCard(artist: r.topArtists[i], size: 120),
                    ),
                  ),
                if (r.monthlyCards.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _Months(
                      cards: r.monthlyCards,
                      onOpen: (c) => showPlatformSheet<void>(
                        context: context,
                        builder: (_) => MonthSheet(year: c.year, month: c.month),
                        maxHeight: 760,
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, 0),
                  sliver: SliverList.list(children: [
                    if (r.topGenres.isNotEmpty)
                      GenreMixCard(genres: [for (final g in r.topGenres) {'genre': g.genre, 'pct': g.pct}]),
                    ListeningClock(byHour: r.hourlyHeatmap),
                  ]),
                ),
              ],
      ),
    );
  }

  static String _comma(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// Four headline numbers for the year as soft tiles on the Replay colour.
class _Figures extends StatelessWidget {
  final YearlyReplayResponse replay;
  const _Figures({required this.replay});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final cells = [
      (compactCount(replay.totalPlays), 'plays'),
      (listeningTime(replay.totalMinutes.round()), 'listened'),
      ('${replay.listeningDays}', 'days with music'),
      (hourLabel(replay.peakHourIst), 'your peak hour'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 600 ? 4 : 2;
      final w = (c.maxWidth - Space.md * (columns - 1)) / columns;
      return Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (final (value, label) in cells)
            Container(
              width: w,
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.group)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: figureStyle(t, 28)),
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(label, style: t.footnote),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// The year month by month: one tile per month with listening, minutes and
/// that month's top artist; months without listening are drawn quietly.
class _Months extends ConsumerWidget {
  final List<ReplayMonthlyCard> cards;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const _Months({required this.cards, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final busiest = cards.fold<double>(0, (m, c) => c.totalMinutes > m ? c.totalMinutes : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Month by Month'),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) {
              final c = cards[i];
              final active = c.totalPlays > 0;
              final cover = c.topTrack == null
                  ? null
                  : ref.watch(songCoverUrlProvider('${c.topTrack!.title}|${c.topTrack!.artist}')).asData?.value;
              return CupertinoClickable(
                onTap: active ? () => onOpen(c) : null,
                scaleFactor: 0.97,
                semanticLabel: '${c.monthName}, ${c.totalPlays} plays',
                child: Container(
                  width: 128,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.group)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(c.monthName.substring(0, 3), style: t.headline)),
                          if (active) CoverArt(url: cover, size: 28, radius: Radii.thumb),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        active ? listeningTime(c.totalMinutes.round()) : '—',
                        style: figureStyle(t, 22).copyWith(color: active ? t.textPrimary : t.textMuted),
                      ),
                      Text(
                        active ? (c.topArtist?.artist ?? '${c.totalPlays} plays') : 'No listening',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote,
                      ),
                      const SizedBox(height: Space.sm),
                      // How this month compares with the busiest one.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            Container(height: 3, color: t.fill),
                            FractionallySizedBox(
                              widthFactor: busiest == 0 ? 0 : c.totalMinutes / busiest,
                              child: Container(height: 3, color: t.accent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
