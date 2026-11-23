import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/stats/widgets/ranked_bar_list.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/artwork_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/collection_art/peak_wave.dart';
import '../../../widgets/ui/states.dart';
import '../logic/best_moments.dart';
import '../logic/hotspots.dart';
import '../logic/reel.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Sat 8 Nov" (with the year when it is not this one).
String dayLabel(DateTime d, DateTime now) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';

/// "2h 15m" / "40m" from seconds.
String sessionLength(int seconds) => listeningTime((seconds / 60).round());

/// Your own peaks, from your own history: the parts you scrub back to most,
/// your busiest days and longest sessions. Replay's style, device data only.
class BestMomentsScreen extends ConsumerWidget {
  const BestMomentsScreen({super.key, this.now});

  /// A seam so a golden does not change with the date.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.watch(bestMomentsProvider);
    final today = now ?? DateTime.now();
    return ArtworkPage(
      paletteCoverId: null,
      art: (size) => PeakWave(size: size),
      title: 'Best Moments',
      subtitle: 'Your own peaks',
      onRefresh: () async => ref.invalidate(bestMomentsProvider),
      slivers: best.when(
        loading: () => const [SliverToBoxAdapter(child: LoadingState())],
        error: (_, _) => [
          SliverToBoxAdapter(
            child: MessageState.error(
              title: 'Best moments aren’t available',
              message: 'Your listening history couldn’t be read on this device. Try again.',
              onRetry: () => ref.invalidate(bestMomentsProvider),
            ),
          ),
        ],
        data: (b) => b.isEmpty
            ? const [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.flame,
                    title: 'Your peaks start with your listening',
                    message:
                        'Play songs and scrub back to the parts you love. Moments you return to, your busiest days and longest sessions collect here.',
                  ),
                ),
              ]
            : [
                if (b.hotspots.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Replayed Most')),
                  SliverList.builder(
                    itemCount: b.hotspots.length,
                    itemBuilder: (_, i) => _HotspotRow(hotspot: b.hotspots[i]),
                  ),
                ] else
                  const SliverToBoxAdapter(child: _HotspotNote()),
                if (b.days.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Busiest Days')),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
                    sliver: SliverToBoxAdapter(
                      child: RankedBarList(
                        items: [
                          for (final d in b.days)
                            RankedBarItem(
                              label: dayLabel(d.day, today),
                              detail: '${songCount(d.plays)} · ${sessionLength(d.seconds)}',
                              value: d.seconds.toDouble(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (b.sessions.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Longest Sessions')),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
                    sliver: SliverToBoxAdapter(
                      child: RankedBarList(
                        items: [
                          for (final s in b.sessions)
                            RankedBarItem(
                              label: '${dayLabel(s.start, today)}, ${hourLabel(s.start.hour)}',
                              detail: '${songCount(s.songs)} · ${sessionLength(s.seconds)}',
                              value: s.seconds.toDouble(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
              ],
      ),
    );
  }
}

/// Said when the only thing missing is scrub-back history, so it is not read
/// as broken: that part is recorded from now on, not from old plays.
class _HotspotNote extends StatelessWidget {
  const _HotspotNote();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pageGutter(context), Space.lg, pageGutter(context), 0),
      child: Text(
        'Parts you replay will show here. NaviVibe notices when you jump back in a song, from now on.',
        style: t.footnote,
      ),
    );
  }
}

class _HotspotRow extends ConsumerWidget {
  const _HotspotRow({required this.hotspot});
  final Hotspot hotspot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(allSongsProvider).asData?.value.where((s) => s.id == hotspot.songId).firstOrNull;
    final title = song?.title ?? 'A song';
    final end = hotspot.startMs + hotspotWindowMs;
    final span = momentSpan(hotspot.startMs, end);
    final detail = '$span · ${hotspot.count} replays';
    final art = song == null ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    return CupertinoClickable(
      onTap: song == null ? null : () => _play(ref, song, end),
      scaleFactor: 0.99,
      semanticLabel: '$title, $detail. Play this part',
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
          child: Row(
            children: [
              CoverArt(url: art, size: 46, radius: Radii.thumb),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                    Text(
                      song?.artist ?? 'Not in this library',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.subheadline,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(span, style: t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('${hotspot.count} replays', style: t.footnote),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Plays just that stretch, fitted to the song.
  void _play(WidgetRef ref, Song song, int endMs) {
    final durMs = song.duration * 1000;
    final e = durMs > 0 && endMs > durMs ? durMs : endMs;
    final s = hotspot.startMs.clamp(0, e - 1);
    ref
        .read(playerProvider.notifier)
        .playReel(
          ReelPlan([song], [ReelSegment(songId: song.id, startMs: s, endMs: e, suggested: true)]),
          name: 'Best moment',
        );
  }
}
