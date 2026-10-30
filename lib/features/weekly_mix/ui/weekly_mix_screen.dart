import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../utils/format.dart' show songCount;
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../listen/data/listen_models.dart';
import '../../listen/ui/pick_row.dart';
import '../logic/weekly_mix_providers.dart';

/// The cover a weekly mix wears: generated from the week, so each week looks
/// different and the same week always looks the same.
Widget weeklyMixCover(WeeklyMix mix, {double borderRadius = Radii.cover}) => GeneratedCover(
      name: 'Weekly Mix ${mix.weekOf?.toIso8601String() ?? ''}',
      songIds: [for (final p in mix.items.take(6)) p.songId],
      borderRadius: borderRadius,
    );

/// Plays the mix, toasting when none of its songs could be loaded.
Future<void> playWeeklyMix(BuildContext context, WidgetRef ref, WeeklyMix mix, {ListenPick? from, bool shuffle = false}) async {
  var ok = false;
  try {
    ok = await ref.read(weeklyMixPlayerProvider).play(mix, from: from, shuffle: shuffle);
  } catch (_) {}
  if (!ok && context.mounted) showToast(context, 'Couldn’t load these songs. Check your connection and try again.');
}

/// This week's mix: the songs with why each is here, Play and Shuffle for all
/// of them, and Save as playlist.
class WeeklyMixScreen extends ConsumerWidget {
  const WeeklyMixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklyMixProvider);
    final mix = async.asData?.value;
    return LargeTitlePage(
      title: 'Weekly Mix',
      onRefresh: () => ref.refresh(weeklyMixProvider.future),
      slivers: [
        if (mix != null && mix.items.isNotEmpty) ...[
          SliverToBoxAdapter(child: _Header(mix: mix)),
          SliverList.builder(
            itemCount: mix.items.length,
            itemBuilder: (context, i) {
              final p = mix.items[i];
              return PickRow(
                songId: p.songId,
                title: p.title,
                artist: p.artist,
                why: p.why,
                tag: p.explore ? p.languageName : null,
                explore: p.explore,
                showSeparator: i < mix.items.length - 1,
                onTap: () => playWeeklyMix(context, ref, mix, from: p),
              );
            },
          ),
        ] else
          SliverToBoxAdapter(
            child: async.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: Space.sm), child: TrackListSkeleton(rows: 10)),
              error: (e, _) => MessageState.error(
                title: 'Your mix didn’t load',
                message: '$e',
                onRetry: () => ref.invalidate(weeklyMixProvider),
              ),
              data: (_) => const MessageState(
                art: EmptyArtKind.record,
                title: 'No mix yet',
                message: 'Play a few songs and your first weekly mix appears on Monday morning.',
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  final WeeklyMix mix;
  const _Header({required this.mix});

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = await ref.read(weeklyMixPlayerProvider).saveAsPlaylist(widget.mix);
      if (!mounted) return;
      setState(() => _saved = true);
      showToast(context, 'Saved as “$name”');
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t save the playlist. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final mix = widget.mix;
    final week = weekLabel(mix.weekOf);
    final cover = (MediaQuery.sizeOf(context).width * 0.52).clamp(160.0, 240.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.lg),
      child: Column(
        children: [
          SizedBox.square(dimension: cover, child: weeklyMixCover(mix, borderRadius: Radii.hero)),
          const SizedBox(height: Space.lg),
          Text(
            [if (week.isNotEmpty) 'Week of $week', songCount(mix.items.length)].join(' · '),
            style: t.headline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Songs you haven’t played much, picked from what you listen to. A new mix arrives every Monday morning.',
            style: t.footnote,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.lg),
          PlayShuffleButtons(
            onPlay: () => playWeeklyMix(context, ref, mix),
            onShuffle: () => playWeeklyMix(context, ref, mix, shuffle: true),
          ),
          const SizedBox(height: Space.md),
          TintedButton(
            label: _saved ? 'Saved to playlists' : (_saving ? 'Saving…' : 'Save as playlist'),
            onTap: _saving || _saved ? null : _save,
          ),
        ],
      ),
    );
  }
}
