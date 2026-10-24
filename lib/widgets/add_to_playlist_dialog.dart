import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import 'art/navi_icons.dart';
import 'cover_art.dart';
import 'desktop_dialogs.dart';
import 'ui/action_sheet.dart';
import 'ui/states.dart';

/// Opens the "Add to Playlist" sheet for [song].
Future<void> showAddToPlaylist(BuildContext context, Song song) =>
    showPlatformSheet<void>(context: context, builder: (_) => AddToPlaylistSheet(song: song));

/// Every playlist with a checkmark showing whether [song] is in it. Taps are
/// staged locally and committed together on Done, so a mis-tap costs nothing.
class AddToPlaylistSheet extends ConsumerStatefulWidget {
  final Song song;
  const AddToPlaylistSheet({super.key, required this.song});

  @override
  ConsumerState<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<AddToPlaylistSheet> {
  final _name = TextEditingController();
  final _adds = <String>{};
  final _removes = <String>{};
  bool _naming = false;
  bool _busy = false;

  bool get _dirty => _adds.isNotEmpty || _removes.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _checked(String id, bool original) =>
      _adds.contains(id) || (original && !_removes.contains(id));

  void _toggle(String id, bool original) {
    HapticFeedback.selectionClick();
    setState(() {
      if (original) {
        _removes.contains(id) ? _removes.remove(id) : _removes.add(id);
      } else {
        _adds.contains(id) ? _adds.remove(id) : _adds.add(id);
      }
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(playlistControllerProvider).createAndAdd(name, widget.song.id);
      if (!mounted) return;
      _name.clear();
      setState(() {
        _busy = false;
        _naming = false;
      });
      showToast(context, 'Added to $name');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, 'Couldn’t create “$name”. Check your connection and try again.');
    }
  }

  Future<void> _done() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(playlistControllerProvider)
          .batchUpdate(songId: widget.song.id, adds: _adds, removes: _removes);
      if (!mounted) return;
      showToast(context, n == 1 ? 'Updated 1 playlist' : 'Updated $n playlists');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, 'Couldn’t update playlists. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final playlists = ref.watch(playlistsProvider);
    final svc = ref.read(subsonicServiceProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.md),
          child: Row(
            children: [
              Expanded(child: Text('Add to Playlist', style: t.title3)),
              _busy
                  ? const Padding(padding: EdgeInsets.all(Space.md), child: CupertinoActivityIndicator())
                  : CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                      onPressed: _done,
                      child: Text('Done', style: t.headline.copyWith(color: t.accent)),
                    ),
            ],
          ),
        ),
        SheetHeader(
          title: widget.song.title,
          subtitle: widget.song.artist,
          artUrl: widget.song.coverArt.isEmpty ? null : svc.getCoverArtUrl(widget.song.coverArt),
        ),
        SheetGroup(children: [
          _naming
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _name,
                          autofocus: true,
                          placeholder: 'Playlist name',
                          textCapitalization: TextCapitalization.sentences,
                          style: t.body,
                          placeholderStyle: t.body.copyWith(color: t.textMuted),
                          cursorColor: t.accent,
                          decoration: null,
                          padding: const EdgeInsets.symmetric(vertical: Space.sm),
                          onSubmitted: (_) => _create(),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                        onPressed: _busy ? null : _create,
                        child: Text('Create', style: t.headline.copyWith(color: t.accent)),
                      ),
                    ],
                  ),
                )
              : SheetAction(
                  label: 'New Playlist…',
                  icon: NaviGlyph.plus,
                  keepOpen: true,
                  onTap: () => setState(() => _naming = true),
                ),
        ]),
        playlists.when(
          loading: () => const LoadingState(),
          error: (_, _) => MessageState.error(
            title: 'Couldn’t load playlists',
            onRetry: () => ref.invalidate(playlistsProvider),
          ),
          data: (list) => list.isEmpty
              ? const MessageState(
                  icon: NaviGlyph.playlist,
                  title: 'No playlists yet',
                  message: 'Create one above to start collecting songs.',
                )
              : SheetGroup(children: [
                  for (final p in list)
                    _PlaylistRow(
                      playlist: p,
                      songId: widget.song.id,
                      artUrl: (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt),
                      isChecked: (original) => _checked(p.id, original),
                      onToggle: (original) => _toggle(p.id, original),
                    ),
                ]),
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

class _PlaylistRow extends ConsumerWidget {
  final Playlist playlist;
  final String songId;
  final String? artUrl;
  final bool Function(bool original) isChecked;
  final void Function(bool original) onToggle;

  const _PlaylistRow({
    required this.playlist,
    required this.songId,
    required this.artUrl,
    required this.isChecked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final membership = ref.watch(songsInPlaylistProvider(playlist.id));
    final original = membership.asData?.value.any((s) => s.id == songId);
    final checked = original != null && isChecked(original);

    return InkWell(
      onTap: original == null ? null : () => onToggle(original),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: Row(
          children: [
            CoverArt(url: artUrl, size: 44, radius: Radii.thumb, placeholderIcon: NaviGlyph.playlist),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                  Text(songCount(playlist.songCount), style: t.footnote),
                ],
              ),
            ),
            SizedBox(
              width: 28,
              child: membership.isLoading
                  ? const CupertinoActivityIndicator(radius: 8)
                  : membership.hasError
                      ? NaviIcon(NaviGlyph.alert, size: 20, color: t.danger)
                      : AnimatedSwitcher(
                          duration: Motion.fast,
                          child: NaviIcon(
                            checked ? NaviGlyph.checkCircle : NaviGlyph.ring,
                            filled: checked,
                            key: ValueKey(checked),
                            size: 24,
                            color: checked ? t.accent : t.textMuted,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
