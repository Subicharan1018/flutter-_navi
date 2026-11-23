import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/format.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/artwork_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/collection_art/peak_wave.dart';
import '../../../widgets/ui/states.dart';
import '../data/peak_mark.dart';
import '../data/peak_store.dart';
import '../logic/hotspots.dart';
import '../logic/reel.dart';
import 'best_moments_screen.dart';
import 'moments_sheet.dart';
import 'play_highlights.dart';

/// Highlights: every song you saved a best part of, played back to back.
class HighlightsScreen extends ConsumerStatefulWidget {
  const HighlightsScreen({super.key});

  @override
  ConsumerState<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends ConsumerState<HighlightsScreen> {
  /// Songs without a saved moment add the stretch you scrub back to most.
  bool _suggest = false;

  Future<void> _play(List<Song> library, {bool shuffle = false}) async {
    var songs = _scope(library);
    if (shuffle) songs = ([...songs]..shuffle());
    await playHighlights(context, ref, songs, name: 'Highlights', includeSuggested: _suggest);
  }

  /// Marked songs, plus (when suggestions are on) songs with a hotspot.
  List<Song> _scope(List<Song> library) {
    final marks = ref.read(peakMarksProvider);
    final marked = songsWithMarks(library, marks);
    if (!_suggest) return marked;
    final hot = {for (final h in findHotspots(ref.read(seekLogProvider))) h.songId};
    final ids = {for (final s in marked) s.id};
    return [...marked, for (final s in library) if (hot.contains(s.id) && !ids.contains(s.id)) s];
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(allSongsProvider);
    final marks = ref.watch(peakMarksProvider);
    final library = songs.asData?.value ?? const <Song>[];
    final marked = songsWithMarks(library, marks);
    final svc = ref.read(subsonicServiceProvider);
    final hasHot = findHotspots(ref.watch(seekLogProvider)).isNotEmpty;
    final plan = buildReel(marked, marks);

    return ArtworkPage(
      paletteCoverId: marked.isEmpty ? null : marked.first.coverArt,
      art: (size) => PeakWave(coverUrl: marked.isEmpty ? null : svc.getCoverArtUrl(marked.first.coverArt), size: size),
      title: 'Highlights',
      subtitle: marked.isEmpty ? null : '${plan.songs.length} moments · ${_minutes(plan.totalMs)}',
      detail: marked.isEmpty ? null : 'The best parts of ${songCount(marked.length)}, back to back',
      buttons: marked.isEmpty && !hasHot
          ? null
          : PlayShuffleButtons(
              onPlay: () => _play(library),
              onShuffle: () => _play(library, shuffle: true),
              trailing: CircleIconButton(
                icon: NaviGlyph.clock,
                label: 'Best listening moments',
                onTap: () => navigateInApp(context, const BestMomentsScreen()),
              ),
            ),
      onRefresh: () async => ref.invalidate(allSongsProvider),
      slivers: songs.when(
        loading: () => const [SliverToBoxAdapter(child: LoadingState())],
        error: (_, _) => [
          SliverToBoxAdapter(
            child: MessageState.error(
              title: 'Highlights aren’t available',
              message: 'Your library didn’t load, so your saved moments can’t be matched to songs. Try again.',
              onRetry: () => ref.invalidate(allSongsProvider),
            ),
          ),
        ],
        data: (_) => marked.isEmpty
            ? [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.flame,
                    title: 'Save the best parts of songs',
                    message:
                        'Tap the flame while a song plays to save the moment you love. Your highlights play here, back to back.',
                    actionLabel: hasHot ? 'See your best moments' : null,
                    onAction: hasHot ? () => navigateInApp(context, const BestMomentsScreen()) : null,
                  ),
                ),
              ]
            : [
                if (hasHot)
                  SliverToBoxAdapter(
                    child: _SuggestRow(value: _suggest, onChanged: (v) => setState(() => _suggest = v)),
                  ),
                SliverList.builder(
                  itemCount: marked.length,
                  itemBuilder: (_, i) => _MomentSongRow(
                    song: marked[i],
                    marks: marks.of(marked[i].id),
                    onTap: () => playHighlights(context, ref, [marked[i]], name: marked[i].title),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
              ],
      ),
    );
  }

  static String _minutes(int ms) {
    final s = (ms / 1000).round();
    return s < 60 ? '$s sec' : '${s ~/ 60} min ${s % 60} sec';
  }
}

class _SuggestRow extends StatelessWidget {
  const _SuggestRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context), vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add most-replayed parts', style: t.body),
                Text('For songs without a saved moment, play the part you scrub back to most.', style: t.footnote),
              ],
            ),
          ),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MomentSongRow extends ConsumerWidget {
  const _MomentSongRow({required this.song, required this.marks, required this.onTap});
  final Song song;
  final List<PeakMark> marks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final art = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final span = marks.length == 1
        ? momentSpan(marks.first.startMs, marks.first.endMs)
        : '${marks.length} moments';
    return CupertinoClickable(
      onTap: onTap,
      onLongPress: () => showMomentsSheet(context, song),
      scaleFactor: 0.99,
      semanticLabel: '${song.title} by ${song.artist}, $span. Play its highlights',
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
                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                    Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Text(span, style: t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: Space.xs),
              CupertinoTap(
                label: 'Edit moments of ${song.title}',
                onTap: () => showMomentsSheet(context, song),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: NaviIcon(NaviGlyph.sliders, size: 18, color: t.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
