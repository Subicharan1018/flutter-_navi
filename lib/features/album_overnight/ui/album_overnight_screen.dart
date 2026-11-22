import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive, showToast;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart' show TintedButton;
import '../../../widgets/ui/states.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../data/album_overnight_models.dart';
import '../logic/album_overnight_providers.dart';

/// Widest the page gets on a desktop window.
const double kAlbumOvernightMaxWidth = 720;

String _say(Object e) => e is OnlineFetchException ? e.message : 'That didn’t work. Check your connection and try again.';

/// "Cancelled. 4 tracks dropped; 2 already on their way will finish."
String cancelMessage(CancelResult r) {
  final dropped = r.stopped == 1 ? '1 track dropped' : '${r.stopped} tracks dropped';
  if (r.alreadyOnItsWay == 0) return r.stopped == 0 ? 'Nothing was waiting.' : 'Cancelled. $dropped.';
  final way = r.alreadyOnItsWay == 1 ? '1 is already on its way and will finish' : '${r.alreadyOnItsWay} are already on their way and will finish';
  return 'Cancelled. $dropped; $way.';
}

/// Settings › Album Overnight › Queue: the albums being completed, what is waiting for tonight, and Cancel.
/// How albums are found: docs/album-overnight.md.
class AlbumOvernightScreen extends ConsumerWidget {
  const AlbumOvernightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumOvernightProvider);
    return LargeTitlePage(
      title: 'Album Overnight',
      onRefresh: () => ref.read(albumOvernightProvider.notifier).refresh(),
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAlbumOvernightMaxWidth),
              child: async.when(
                skipLoadingOnRefresh: true,
                loading: () => const Padding(padding: EdgeInsets.only(top: Space.sm), child: TrackListSkeleton(rows: 6)),
                error: (e, _) => MessageState.error(
                  title: 'Your queue didn’t load',
                  message: _say(e),
                  onRetry: () => ref.invalidate(albumOvernightProvider),
                ),
                data: (a) => _Body(a),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  final AlbumOvernight a;
  const _Body(this.a);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    if (!a.enabled && a.albums.isEmpty) {
      return MessageState(
        icon: NaviGlyph.downloadCircle,
        title: 'Album Overnight is off',
        message: 'Turn it on and when a song you fetch comes in, the rest of its film album is fetched at night.',
        actionLabel: 'Turn on',
        onAction: () async {
          try {
            await ref.read(albumOvernightProvider.notifier).setEnabled(true);
          } catch (e) {
            if (context.mounted) showToast(context, _say(e));
          }
        },
      );
    }
    if (a.albums.isEmpty) {
      return const MessageState(
        art: EmptyArtKind.record,
        title: 'No albums queued',
        message: 'Fetch a song from a film and the rest of its album shows up here, ready for tonight.',
      );
    }
    final open = a.open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.waiting == 0 ? 'Nothing waiting' : '${a.waiting} ${a.waiting == 1 ? 'track' : 'tracks'} to fetch', style: t.headline),
              const SizedBox(height: Space.xs),
              Text(
                a.downloadNote ?? 'Tracks download between ${a.nightFrom} and ${a.nightTo} am, up to ${a.perNight} a night.',
                style: t.subheadline,
              ),
              if (open.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Row(children: [
                  TintedButton(
                    label: 'Cancel all',
                    onTap: () async {
                      final ok = await confirmDestructive(
                        context,
                        title: 'Cancel all albums?',
                        message: 'Tracks that haven’t started are dropped and these albums won’t be queued again.',
                        confirmLabel: 'Cancel all',
                      );
                      if (!ok || !context.mounted) return;
                      try {
                        final r = await ref.read(albumOvernightProvider.notifier).cancelAll();
                        if (context.mounted) showToast(context, cancelMessage(r));
                      } catch (e) {
                        if (context.mounted) showToast(context, _say(e));
                      }
                    },
                  ),
                ]),
              ],
            ],
          ),
        ),
        for (final al in a.albums) _AlbumRow(key: ValueKey('album-${al.id}'), album: al),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.huge),
          child: Text(
            'Only tracks you don’t have are fetched, at most ${a.maxPerAlbum} an album and ${a.maxWaiting} waiting at once. '
            'The night’s limit, the disk guard and one batch at a time are the same as for a Spotify wishlist.',
            style: t.footnote.copyWith(color: t.textMuted),
          ),
        ),
      ],
    );
  }
}

class _AlbumRow extends ConsumerStatefulWidget {
  static const double cover = 56;
  final QueuedAlbum album;
  const _AlbumRow({super.key, required this.album});

  @override
  ConsumerState<_AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends ConsumerState<_AlbumRow> {
  bool _open = false;

  Future<void> _cancel() async {
    try {
      final r = await ref.read(albumOvernightProvider.notifier).cancelAlbum(widget.album.id);
      if (mounted) showToast(context, cancelMessage(r));
    } catch (e) {
      if (mounted) showToast(context, _say(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final al = widget.album;
    final sub = [if (al.fromSong.isNotEmpty) 'after “${al.fromSong}”', if (al.artist.isNotEmpty) al.artist].join(' · ');
    return Semantics(
      container: true,
      label: '${al.album}, ${al.line}',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.gutter),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: CoverArt(url: al.coverUrl, size: _AlbumRow.cover, radius: Radii.thumb),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: _AlbumRow.cover + Space.lg),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoClickable(
                            onTap: al.tracks.isEmpty ? null : () => setState(() => _open = !_open),
                            semanticLabel: _open ? 'Hide tracks of ${al.album}' : 'Show tracks of ${al.album}',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(al.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                                const SizedBox(height: Space.xxs),
                                Text(al.line, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textMuted)),
                              ],
                            ),
                          ),
                        ),
                        if (al.toCome > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: Space.sm, right: Space.gutter),
                            child: TintedButton(label: 'Cancel', height: 32, onTap: _cancel),
                          )
                        else
                          const SizedBox(width: Space.gutter),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_open)
            for (final tr in al.tracks) _TrackLine(tr),
        ],
      ),
    );
  }
}

class _TrackLine extends StatelessWidget {
  final AlbumTrack track;
  const _TrackLine(this.track);

  String get _state => switch (track.stage) {
        TrackStage.ready => 'In your library',
        TrackStage.queued => 'On its way',
        TrackStage.failed => 'Will try again',
        TrackStage.cancelled => 'Cancelled',
        TrackStage.waiting => 'Tonight',
      };

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final done = track.stage == TrackStage.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter + _AlbumRow.cover + Space.md, Space.xs, Space.gutter, Space.xs),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(track.number > 0 ? '${track.number}' : '', style: t.footnote.copyWith(color: t.textMuted))),
          Expanded(child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline)),
          const SizedBox(width: Space.sm),
          if (done) NaviIcon(NaviGlyph.check, size: 14, color: t.textSecondary),
          if (done) const SizedBox(width: Space.xs),
          Text(_state, style: t.footnote.copyWith(color: t.textMuted)),
        ],
      ),
    );
  }
}
