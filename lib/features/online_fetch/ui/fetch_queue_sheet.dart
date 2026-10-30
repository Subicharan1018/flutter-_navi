import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/states.dart';
import '../data/fetch_models.dart';
import '../data/fetch_queue_models.dart';
import '../logic/fetch_queue_providers.dart';
import 'send_playlist_sheet.dart';

/// The download queue: what is downloading, what waits (in the order it will
/// run) and what finished lately. Everyone sees their own downloads; an
/// admin sees everyone's and can move one to the top. Anything on its way can
/// be cancelled, anything that stopped can be tried again, and a playlist
/// link (pasted, or copied from Spotify / Deezer) joins the queue from here.
Future<void> showFetchQueue(BuildContext context) => showPlatformSheet<void>(
      context: context,
      maxHeight: 720,
      builder: (_) => const FetchQueueSheet(),
    );

class FetchQueueSheet extends ConsumerWidget {
  const FetchQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final async = ref.watch(fetchQueueProvider);
    final queue = async.asData?.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.xs),
          child: Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text('Download queue', style: t.title3))),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                minimumSize: const Size(44, 44),
                onPressed: () => _addLink(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NaviIcon(NaviGlyph.link, size: 16, color: t.accent),
                    const SizedBox(width: Space.xs),
                    Text('Add a Link', style: t.subheadline.copyWith(color: t.accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (queue != null && !queue.admin && queue.maxLinks != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: Text('You can have ${queue.maxLinks} playlist links in the queue at once.', style: t.footnote),
          ),
        Flexible(
          child: async.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: Space.sm), child: TrackListSkeleton(rows: 4)),
            error: (e, _) => MessageState.error(
              title: 'The queue didn’t load',
              message: '$e',
              onRetry: () => ref.invalidate(fetchQueueProvider),
            ),
            data: (q) => q.items.isEmpty
                ? const MessageState(
                    icon: NaviGlyph.download,
                    title: 'Nothing in the queue',
                    message: 'Add a playlist link, or download an album or playlist from Search online. '
                        'They run one after another.',
                  )
                : _QueueList(queue: q),
          ),
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }

  /// Opens "Send a Playlist"; a playlist link already on the clipboard (copied
  /// from Spotify or Deezer) is sent along so it's one tap.
  static Future<void> _addLink(BuildContext context) async {
    final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final link = looksLikeLink(copied) && playlistLinkProblem(copied) == null ? copied.trim() : null;
    if (context.mounted) await showSendPlaylist(context, link: link);
  }
}

class _QueueList extends ConsumerWidget {
  final FetchQueue queue;
  const _QueueList({required this.queue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final active = queue.active;
    final finished = queue.finished;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xs),
          child: Semantics(header: true, child: Text(text, style: t.footnote)),
        );
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        if (active.isNotEmpty) heading('Up next'),
        for (final (i, item) in active.indexed)
          FetchQueueRow(
            item: item,
            admin: queue.admin,
            showSeparator: i < active.length - 1,
            canMoveUp: item.status == QueueStatus.queued && (item.position ?? 1) > 1,
          ),
        if (finished.isNotEmpty) heading('Finished'),
        for (final (i, item) in finished.indexed)
          FetchQueueRow(item: item, admin: queue.admin, showSeparator: i < finished.length - 1),
      ],
    );
  }
}

/// One queued, running or finished download: its cover, progress and the
/// actions that fit its state.
class FetchQueueRow extends ConsumerWidget {
  final FetchQueueItem item;
  final bool admin;
  final bool showSeparator;
  final bool canMoveUp;

  const FetchQueueRow({
    super.key,
    required this.item,
    required this.admin,
    this.showSeparator = false,
    this.canMoveUp = false,
  });

  Future<void> _run(BuildContext context, Future<String?> Function() action) async {
    final problem = await action();
    if (problem != null && context.mounted) showToast(context, problem);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final controller = ref.read(fetchQueueProvider.notifier);
    final running = item.status == QueueStatus.running;
    final status = describeQueueItem(item, showUser: admin);
    const art = 44.0;
    return Semantics(
      label: [item.title, status].where((s) => s.isNotEmpty).join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.xs, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (item.coverUrl == null || item.coverUrl!.isEmpty)
                  SizedBox(
                    width: art,
                    height: art,
                    child: GeneratedCover(name: item.title, borderRadius: Radii.thumb),
                  )
                else
                  CoverArt(url: item.coverUrl, size: art, radius: Radii.thumb, placeholderIcon: NaviGlyph.playlist),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote.copyWith(
                          color: item.status == QueueStatus.failed ? t.danger : t.textSecondary,
                        ),
                      ),
                      if (running) ...[
                        const SizedBox(height: Space.xs),
                        _Bar(value: item.progress),
                      ],
                    ],
                  ),
                ),
                if (canMoveUp && admin)
                  _Action(
                    glyph: NaviGlyph.caretUp,
                    label: 'Move ${item.title} to the top',
                    onTap: () => _run(context, () => controller.moveToTop(item.id)),
                  ),
                if (item.canRetry)
                  _Action(
                    glyph: NaviGlyph.repeat,
                    label: 'Try ${item.title} again',
                    onTap: () => _run(context, () => controller.retry(item.id)),
                  ),
                if (item.canCancel)
                  _Action(
                    glyph: NaviGlyph.close,
                    label: 'Cancel ${item.title}',
                    onTap: () => _run(context, () => controller.cancel(item.id)),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (showSeparator)
              Padding(
                padding: const EdgeInsets.only(left: art + Space.md),
                child: Container(height: 0.5, color: t.outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// The row's second line: what it is, where it stands, and (for an admin)
/// whose it is.
String describeQueueItem(FetchQueueItem i, {bool showUser = false}) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  final what = switch (i.kind) {
    'album' => 'Album',
    'playlist' => i.isLink ? 'Playlist link' : 'Playlist',
    'label' => 'Label',
    'artist' => 'Artist',
    _ => i.total > 0 ? songs(i.total) : 'Songs',
  };
  final who = showUser && i.user.isNotEmpty ? i.user : null;
  final state = switch (i.status) {
    QueueStatus.queued => i.position == 1 ? 'Next up' : 'Waiting · #${i.position ?? '–'} in the queue',
    QueueStatus.running when i.total == 0 => 'Getting the songs…',
    QueueStatus.running => [
        '${i.handled} of ${songs(i.total)}',
        if (i.current != null) i.current!,
      ].join(' · '),
    QueueStatus.done => i.summary ?? '${songs(i.added + i.owned)} done',
    QueueStatus.failed => i.error ?? 'Didn’t finish. Try again.',
    QueueStatus.cancelled => 'Cancelled',
  };
  return [what, ?who, state].join(' · ');
}

class _Bar extends StatelessWidget {
  final double value;
  const _Bar({required this.value});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(1.5),
      child: LinearProgressIndicator(
        value: value == 0 ? null : value,
        minHeight: 3,
        color: t.accent,
        backgroundColor: t.outline,
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.glyph, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: NaviIcon(glyph, size: 20, color: t.textSecondary, semanticLabel: label),
    );
  }
}
