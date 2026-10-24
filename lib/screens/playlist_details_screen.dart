import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/download_state.dart';
import '../models/playlist.dart';
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
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
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

  Future<void> _addSongs() async {
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => SongPickerScreen(playlistId: _playlist.id, playlistName: _playlist.name),
    ));
    await ref.read(subsonicServiceProvider).invalidatePlaylist(_playlist.id);
    _load();
  }

  Future<void> _edit() async {
    if (await showPlaylistEditor(context, playlist: _playlist)) _load();
  }

  Future<void> _delete() async {
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

    return ArtworkPage(
      paletteCoverId: paletteId,
      // A playlist without its own cover shows a mosaic of its songs, as
      // Apple Music does.
      art: (size) => ownCover
          ? CoverArt(url: _coverUrl, size: size, radius: 0, placeholderIcon: CupertinoIcons.music_note_list)
          : MosaicArt(
              urls: [for (final s in _songs.take(24)) svc.getCoverArtUrl(s.coverArt)],
              size: size,
              radius: 0,
              seed: coverSeed(_playlist.name, _songs.map((s) => s.id)),
            ),
      title: _playlist.name,
      detail: _loading ? null : songCount(_songs.length),
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
              BarCircleButton(icon: CupertinoIcons.add, label: 'Add Songs', onTap: _addSongs),
              BarCircleButton(
                icon: CupertinoIcons.ellipsis,
                label: 'More',
                onTap: () => showCollectionActions(
                  context,
                  title: _playlist.name,
                  subtitle: songCount(_songs.length),
                  artUrl: _coverUrl,
                  loadSongs: () async => _songs,
                  onEdit: _edit,
                  onDelete: _delete,
                  pin: Pin.playlist(_playlist),
                ),
              ),
            ],
      onRefresh: _load,
      slivers: [
        if (!_loading && !_failed && _songs.isNotEmpty)
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
                  if (!_editing && _query.isEmpty)
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
              icon: CupertinoIcons.music_note_list,
              title: 'This playlist is empty',
              message: 'Add songs from your library to start listening.',
              actionLabel: 'Add Songs',
              onAction: _addSongs,
            ),
          )
        else if (visible.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: CupertinoIcons.search,
              title: 'No matches',
              message: 'Nothing in this playlist matches “${_search.text.trim()}”.',
              actionLabel: 'Clear Search',
              onAction: _search.clear,
            ),
          )
        else if (_editing)
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
        else
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final song = visible[i];
                return SwipeActions.queue(
                  rowKey: ValueKey('pl_${song.id}_$i'),
                  context: context,
                  onPlayNext: () => queueSongs(context, ref, [song], next: true),
                  onPlayLast: () => queueSongs(context, ref, [song], next: false),
                  child: SongTile(
                    song: song,
                    showDuration: PlatformUtils.isDesktop,
                    onTap: () => _play(from: song),
                    playlistId: _playlist.id,
                    onRemoveFromPlaylist: () => _remove(song),
                  ),
                );
              },
              childCount: visible.length,
            ),
          ),
        if (!_loading && _songs.isNotEmpty && _query.isEmpty)
          SliverToBoxAdapter(child: CollectionSummary(songs: _songs)),
        if (!_loading && !_failed && !_editing && _query.isEmpty && _songs.length >= 2 && !ref.watch(isOfflineProvider))
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
              child: Icon(CupertinoIcons.minus_circle_fill, color: t.danger, semanticLabel: 'Remove ${song.title}'),
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
                child: Icon(CupertinoIcons.line_horizontal_3, color: t.textMuted, semanticLabel: 'Reorder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
