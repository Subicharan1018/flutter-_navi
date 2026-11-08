import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/share/share_sheet.dart';
import '../features/smart_playlists/ui/smart_widgets.dart' show FolderMoveAction;

import '../core/motion.dart';
import '../core/theme.dart';
import '../models/download_state.dart';
import '../models/playlist.dart';
import '../models/playlist_access.dart';
import '../models/song.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/platform_utils.dart';
import '../utils/playlist_actions.dart';
import '../utils/queue_actions.dart';
import '../widgets/collection_actions.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/table/song_table.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/collection_hero.dart';
import '../widgets/ui/artwork_page.dart';
import '../widgets/ui/controls.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/mosaic_art.dart';
import '../widgets/ui/states.dart';
import '../widgets/ui/swipe_actions.dart';
import 'playlist_editor.dart';
import 'playlist_suggestions.dart';
import 'song_picker_screen.dart';

/// A playlist, Apple Music style. Tap "Edit" to reorder (drag handles) or
/// remove songs (red minus); outside edit mode rows swipe to queue.
class PlaylistDetailsScreen extends ConsumerStatefulWidget {
  final Playlist playlist;
  const PlaylistDetailsScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends ConsumerState<PlaylistDetailsScreen> {
  /// Search appears once a playlist is long enough to need it.
  static const _searchThreshold = 12;

  List<Song> _songs = [];
  bool _loading = true;
  bool _failed = false;
  bool _editing = false;
  final _search = TextEditingController();

  /// The playlist as the server has it now (name, description and cover can
  /// change in the editor); falls back to what this page was opened with.
  Playlist? _live;
  Playlist get _playlist => _live ?? widget.playlist;
  String get _query => _search.text.trim().toLowerCase();

  /// Someone else's playlist: read-only for everyone, whatever their role in a
  /// room. The service refuses the writes too; this keeps the screen honest.
  bool get _readOnly => _playlist.isSharedFor(ref.read(settingsProvider).username);

  Future<void> _makeCopy() async {
    try {
      final copy = await ref.read(playlistControllerProvider).makeCopy(_playlist);
      if (!mounted) return;
      showToast(context, 'Copied to “${copy.name}”');
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t make a copy. Try again.');
    }
  }

  List<Song> get _visible => _query.isEmpty
      ? _songs
      : _songs
          .where((s) =>
              s.title.toLowerCase().contains(_query) ||
              s.artist.toLowerCase().contains(_query) ||
              s.album.toLowerCase().contains(_query))
          .toList();

  String? get _coverUrl {
    final id = _playlist.resolvedCoverArtId(_songs);
    return id == null || id.isEmpty ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(id);
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final songs = await ref.read(subsonicServiceProvider).getPlaylistSongs(_playlist.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _songs.isEmpty;
      });
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> _play({Song? from, bool shuffle = false}) async {
    var playable = _visible;
    // Offline, only downloaded songs can play.
    if (ref.read(isOfflineProvider)) {
      final dl = ref.read(downloadStateProvider);
      playable = playable.where((s) => dl[s.id]?.status == SongDownloadStatus.downloaded).toList();
    }
    if (playable.isEmpty) {
      showToast(context, 'None of these songs are downloaded yet');
      return;
    }
    final n = ref.read(playerProvider.notifier);
    if (shuffle) return n.playPlaylist(playable, shuffle: true, playlistName: _playlist.name);
    // Find the tapped song by identity: offline filtering can drop songs
    // ahead of it, so the on-screen index isn't the queue index.
    final start = from == null ? 0 : playable.indexOf(from);
    await n.setQueue(playable, start < 0 ? 0 : start, playlistName: _playlist.name, unshuffledSongs: _songs);
  }

  // ── Editing ───────────────────────────────────────────────────────────────

  Future<void> _remove(Song song) async {
    if (_readOnly) return;
    final index = _songs.indexOf(song);
    if (index == -1) return;
    HapticFeedback.mediumImpact();
    setState(() => _songs = [..._songs]..removeAt(index));
    try {
      final svc = ref.read(subsonicServiceProvider);
      await svc.updatePlaylist(_playlist.id, songIndexToRemove: index);
      await svc.invalidatePlaylist(_playlist.id);
      ref.invalidate(playlistsProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _songs = [..._songs]..insert(index, song));
      showToast(context, 'Couldn’t remove “${song.title}”. Try again.');
    }
  }

  Future<void> _reorder(int from, int to) async {
    if (_readOnly) return;
    final before = _songs;
    setState(() {
      final next = [..._songs];
      final s = next.removeAt(from);
      next.insert(to, s);
      _songs = next;
    });
    try {
      await ref.read(subsonicServiceProvider).setPlaylistSongs(_playlist.id, _songs.map((s) => s.id).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _songs = before);
      showToast(context, 'Couldn’t save the new order. Try again.');
    }
  }

  /// Table play: the queue is the rows as the table shows them (sorted or not).
  Future<void> _playOrdered(Song song, List<Song> ordered) async {
    var playable = ordered;
    if (ref.read(isOfflineProvider)) {
      final dl = ref.read(downloadStateProvider);
      playable = playable.where((s) => dl[s.id]?.status == SongDownloadStatus.downloaded).toList();
    }
    if (playable.isEmpty) {
      showToast(context, 'None of these songs are downloaded yet');
      return;
    }
    final start = playable.indexOf(song);
    await ref
        .read(playerProvider.notifier)
        .setQueue(playable, start < 0 ? 0 : start, playlistName: _playlist.name, unshuffledSongs: _songs);
  }

  /// Delete key / "Remove from Playlist" on a selection, one at a time, so each

  Future<void> _removeAll(List<Song> songs) async {
    for (final s in songs) {
      await _remove(s);
    }
  }

  /// Drag-reorder from the table: rows at [from] go before row [before].
  Future<void> _moveSongs(List<int> from, int before) async {
    if (_readOnly) return;
    final moving = [for (final i in from) _songs[i]];
    final fromSet = from.toSet();
    final next = <Song>[];
    var insertAt = 0;
    for (var i = 0; i < _songs.length; i++) {
      if (i == before) insertAt = next.length;
      if (!fromSet.contains(i)) next.add(_songs[i]);
    }
    if (before >= _songs.length) insertAt = next.length;
    next.insertAll(insertAt, moving);
    final previous = _songs;
    setState(() => _songs = next);
    try {
      await ref.read(subsonicServiceProvider).setPlaylistSongs(_playlist.id, next.map((s) => s.id).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _songs = previous);
      showToast(context, 'Couldn’t save the new order. Try again.');
    }
  }

  Future<void> _addSongs() async {
    if (_readOnly) return;
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => SongPickerScreen(playlistId: _playlist.id, playlistName: _playlist.name),
    ));
    await ref.read(subsonicServiceProvider).invalidatePlaylist(_playlist.id);
    _load();
  }

  Future<void> _edit() async {
    if (_readOnly) return;
    if (await showPlaylistEditor(context, playlist: _playlist)) _load();
  }

  Future<void> _delete() async {
    if (_readOnly) return;
    if (await deletePlaylistWithConfirm(context, ref, _playlist) && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _live = ref.watch(playlistsProvider).asData?.value.where((p) => p.id == widget.playlist.id).firstOrNull;
    final ids = {for (final s in _songs) s.id};
    final playingThis = ref.watch(playerProvider.select((s) =>
        s.isPlaying && s.currentSong != null && ids.contains(s.currentSong!.id)));
    final visible = _visible;
    final svc = ref.read(subsonicServiceProvider);
    final ownCover = (_playlist.coverArt ?? '').isNotEmpty;
    final paletteId = _playlist.resolvedCoverArtId(_songs);
    final readOnly = _readOnly;

    return ArtworkPage(
      paletteCoverId: paletteId,
      // A playlist without its own cover shows a mosaic of its songs, as
      // Apple Music does.
      art: (size) => ownCover
          ? CoverArt(url: _coverUrl, size: size, radius: 0, placeholderIcon: NaviGlyph.playlist)
          : MosaicArt(
              urls: [for (final s in _songs.take(24)) svc.getCoverArtUrl(s.coverArt)],
              size: size,
              radius: 0,
              // A failed load on Windows shows the plain playlist glyph, not a
              // generated cover that looks like a real one.
              seed: _failed && PlatformUtils.isDesktop ? null : coverSeed(_playlist.name, _songs.map((s) => s.id)),
            ),
      title: _playlist.name,
      // A count only once it is known: a failed load has none (not "0 songs").
      detail: _loading || _failed ? null : songCount(_songs.length),
      description: _playlist.comment.trim(),
      buttons: PlayShuffleButtons(
        playing: playingThis,
        onPlay: _songs.isEmpty
            ? null
            : () => playingThis ? ref.read(playerProvider.notifier).player.pause() : _play(),
        onShuffle: _songs.isEmpty ? null : () => _play(shuffle: true),
        trailing: CollectionDownloadButton(songs: _songs),
      ),
      actions: _editing
          ? [_BarTextAction(label: 'Done', bold: true, onTap: () => setState(() => _editing = false))]
          : [
              if (readOnly)
                BarCircleButton(icon: NaviGlyph.copy, label: 'Make a Copy', onTap: _makeCopy)
              else
                BarCircleButton(icon: NaviGlyph.plus, label: 'Add Songs', onTap: _addSongs),
              BarCircleButton(
                icon: NaviGlyph.more,
                label: 'More',
                onTap: () => showCollectionActions(
                  context,
                  title: _playlist.name,
                  subtitle: songCount(_songs.length),
                  artUrl: _coverUrl,
                  loadSongs: () async => _songs,
                  onEdit: readOnly ? null : _edit,
                  onDelete: readOnly ? null : _delete,
                  pin: Pin.playlist(_playlist),
                  share: ShareTarget.playlist(_playlist),
                  extraActions: [
                    if (readOnly)
                      SheetAction(label: 'Make a Copy', icon: NaviGlyph.copy, onTap: _makeCopy)
                    else
                      FolderMoveAction(playlistId: _playlist.id, page: context),
                  ],
                ),
              ),
            ],
      onRefresh: _load,
      slivers: [
        if (readOnly)
          SliverToBoxAdapter(
            child: _ReadOnlyNote(owner: _playlist.owner ?? '', onCopy: _makeCopy),
          ),
        // Desktop: the table has its own find (Ctrl+F), and no Edit mode.
        if (!_loading && !_failed && _songs.isNotEmpty && !useSongTable())
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.xs, Space.sm),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _songs.length >= _searchThreshold && !_editing
                        ? NaviSearchField(controller: _search, placeholder: 'Find in Playlist')
                        : const SizedBox.shrink(),
                  ),
                  // The table's selection, Delete and drag replace Edit mode on desktop.
                  if (!readOnly && !_editing && _query.isEmpty && !useSongTable())
                    _BarTextAction(label: 'Edit', onTap: () => setState(() => _editing = true)),
                ],
              ),
            ),
          ),
        if (_loading)
          const SliverToBoxAdapter(child: TrackListSkeleton())
        else if (_failed)
          SliverToBoxAdapter(child: MessageState.error(title: 'Couldn’t load this playlist', onRetry: _load))
        else if (_songs.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.playlist,
              title: 'This playlist is empty',
              message: readOnly ? 'There’s nothing in it yet.' : 'Add songs from your library to start listening.',
              actionLabel: readOnly ? null : 'Add Songs',
              onAction: readOnly ? null : _addSongs,
            ),
          )
        else if (visible.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.search,
              art: EmptyArtKind.noResults,
              title: 'No matches',
              message: 'Nothing in this playlist matches “${_search.text.trim()}”.',
              actionLabel: 'Clear Search',
              onAction: _search.clear,
            ),
          )
        else if (_editing && !readOnly)
          SliverReorderableList(
            itemCount: _songs.length,
            onReorderItem: _reorder,
            itemExtent: SongTile.extent,
            proxyDecorator: (child, _, _) => Builder(
              builder: (context) => Material(color: ThemeTokens.of(context).bgElevated, elevation: 8, child: child),
            ),
            itemBuilder: (context, i) => _EditRow(
              key: ValueKey('edit_${_songs[i].id}_$i'),
              song: _songs[i],
              index: i,
              onRemove: () => _remove(_songs[i]),
            ),
          )
        else if (useSongTable())
          SongTableSliver(
            songs: visible,
            playlistId: readOnly ? null : _playlist.id,
            showDateAdded: false,
            onPlay: (song, ordered) => _playOrdered(song, ordered),
            onRemove: readOnly ? null : _removeAll,
            onReorder: _query.isEmpty && !readOnly ? _moveSongs : null,
          )
        else
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final song = visible[i];
                return Entrance(
                  group: 'playlist:${_playlist.id}',
                  index: i,
                  rise: 8,
                  child: SwipeActions.queue(
                    rowKey: ValueKey('pl_${song.id}_$i'),
                    context: context,
                    onPlayNext: () => queueSongs(context, ref, [song], next: true),
                    onPlayLast: () => queueSongs(context, ref, [song], next: false),
                    child: SongTile(
                      song: song,
                      showDuration: PlatformUtils.isDesktop,
                      onTap: () => _play(from: song),
                      playlistId: readOnly ? null : _playlist.id,
                      onRemoveFromPlaylist: readOnly ? null : () => _remove(song),
                    ),
                  ),
                );
              },
              childCount: visible.length,
            ),
          ),
        if (!_loading && _songs.isNotEmpty && _query.isEmpty)
          SliverToBoxAdapter(child: CollectionSummary(songs: _songs)),
        if (!readOnly && !_loading && !_failed && !_editing && _query.isEmpty && _songs.length >= 2 && !ref.watch(isOfflineProvider))
          SliverToBoxAdapter(
            child: PlaylistSuggestions(
              playlistId: _playlist.id,
              playlistName: _playlist.name,
              songs: _songs,
              onAdded: _load,
            ),
          ),
      ],
    );
  }
}

/// Said on top of someone else's playlist: it is read-only, here is how to
/// change it.
class _ReadOnlyNote extends StatelessWidget {
  final String owner;
  final VoidCallback onCopy;
  const _ReadOnlyNote({required this.owner, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
      child: Row(children: [
        Expanded(
          child: Text(
            owner.isEmpty ? 'Read-only. Make a copy to change it.' : '$owner’s playlist · read-only',
            style: t.footnote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.sm),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          minimumSize: const Size(44, 44),
          onPressed: onCopy,
          child: Text('Make a copy', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A text action ("Edit", "Done") that takes its colour from the page it
/// sits on — white on an artwork-tinted page.
class _BarTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool bold;
  const _BarTextAction({required this.label, required this.onTap, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      minimumSize: const Size(44, 36),
      onPressed: onTap,
      child: Text(label, style: (bold ? t.headline : t.body).copyWith(color: t.accent)),
    );
  }
}

/// A row in edit mode: remove on the left, drag handle on the right.
class _EditRow extends ConsumerWidget {
  final Song song;
  final int index;
  final VoidCallback onRemove;
  const _EditRow({super.key, required this.song, required this.index, required this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    return ColoredBox(
      color: t.bgBase,
      child: SizedBox(
        height: SongTile.extent,
        child: Row(
          children: [
            CupertinoButton(
              padding: const EdgeInsets.only(left: Space.md, right: Space.sm),
              onPressed: onRemove,
              child: NaviIcon(NaviGlyph.minusCircle, filled: true, color: t.danger, semanticLabel: 'Remove ${song.title}'),
            ),
            CoverArt(
              url: svc.getCoverArtUrl(song.coverArt.isNotEmpty ? song.coverArt : song.id),
              size: 46,
              radius: Radii.thumb,
            ),
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
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: NaviIcon(NaviGlyph.grip, color: t.textMuted, semanticLabel: 'Reorder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
