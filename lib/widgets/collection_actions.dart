import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/share/share_sheet.dart';
import '../models/song.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../utils/queue_actions.dart';
import 'desktop_dialogs.dart';
import 'ui/action_sheet.dart';

/// Long-press menu for a playlist or album: play, shuffle, queue, and (for
/// the user's own playlists) edit / delete. Songs load only when an action
/// needs them.
Future<void> showCollectionActions(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? artUrl,
  IconData placeholderIcon = CupertinoIcons.music_note_list,
  required Future<List<Song>> Function() loadSongs,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  Pin? pin,
  ShareTarget? share,
}) =>
    showPlatformSheet(
      context: context,
      builder: (_) => _CollectionActions(
        share: share,
        title: title,
        subtitle: subtitle,
        artUrl: artUrl,
        placeholderIcon: placeholderIcon,
        loadSongs: loadSongs,
        onEdit: onEdit,
        onDelete: onDelete,
        pin: pin,
      ),
    );

class _CollectionActions extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final String? artUrl;
  final IconData placeholderIcon;
  final Future<List<Song>> Function() loadSongs;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// When given, offers Pin / Unpin for the top of Library.
  final Pin? pin;

  /// When given, offers Share… (a public link made by the server).
  final ShareTarget? share;

  const _CollectionActions({
    this.share,
    required this.title,
    this.subtitle,
    this.artUrl,
    required this.placeholderIcon,
    required this.loadSongs,
    this.onEdit,
    this.onDelete,
    this.pin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = Navigator.of(context).context;

    Future<void> withSongs(Future<void> Function(List<Song>) action) async {
      try {
        final songs = await loadSongs();
        if (songs.isEmpty) {
          if (page.mounted) showToast(page, '“$title” has no songs yet');
          return;
        }
        await action(songs);
      } catch (_) {
        if (page.mounted) showToast(page, 'Couldn’t load “$title”. Check your connection.');
      }
    }

    final player = ref.read(playerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title, subtitle: subtitle, artUrl: artUrl, placeholderIcon: placeholderIcon),
        SheetGroup(children: [
          SheetAction(
            label: 'Play',
            icon: CupertinoIcons.play,
            onTap: () => withSongs((s) => player.setQueue(s, 0, playlistName: title, unshuffledSongs: s)),
          ),
          SheetAction(
            label: 'Shuffle',
            icon: CupertinoIcons.shuffle,
            onTap: () => withSongs((s) => player.playPlaylist(s, shuffle: true, playlistName: title)),
          ),
        ]),
        SheetGroup(children: [
          SheetAction(
            label: 'Play Next',
            icon: CupertinoIcons.text_insert,
            onTap: () => withSongs((s) => queueSongs(page, ref, s, next: true, label: title)),
          ),
          SheetAction(
            label: 'Play Last',
            icon: CupertinoIcons.text_append,
            onTap: () => withSongs((s) => queueSongs(page, ref, s, next: false, label: title)),
          ),
        ]),
        if (pin != null || share != null)
          SheetGroup(children: [
            if (share != null)
              SheetAction(
                label: 'Share…',
                icon: CupertinoIcons.share,
                onTap: () => showShareSheet(page, share!),
              ),
            if (pin != null) _PinAction(pin: pin!, page: page),
          ]),
        if (onEdit != null || onDelete != null)
          SheetGroup(children: [
            if (onEdit != null) SheetAction(label: 'Edit Playlist', icon: CupertinoIcons.pencil, onTap: onEdit),
            if (onDelete != null)
              SheetAction(label: 'Delete Playlist', icon: CupertinoIcons.trash, destructive: true, onTap: onDelete),
          ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PinAction extends ConsumerWidget {
  final Pin pin;
  final BuildContext page;
  const _PinAction({required this.pin, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinsProvider.select((p) => p.any((e) => e.key == pin.key)));
    final noun = switch (pin.kind) {
      PinKind.album => 'Album',
      PinKind.playlist => 'Playlist',
      PinKind.artist => 'Artist',
    };
    return SheetAction(
      label: pinned ? 'Unpin $noun' : 'Pin $noun',
      icon: pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
      onTap: () {
        final ok = ref.read(pinsProvider.notifier).toggle(pin);
        if (!page.mounted) return;
        showToast(
          page,
          !ok
              ? 'Library holds ${PinsNotifier.max} pins. Unpin one to add another.'
              : (pinned ? 'Unpinned from Library' : 'Pinned to Library'),
        );
      },
    );
  }
}
