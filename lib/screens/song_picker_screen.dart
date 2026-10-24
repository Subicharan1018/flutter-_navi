import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/cover_art.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/controls.dart';
import '../widgets/ui/states.dart';

/// Apple Music's "Add Music" picker: search the library, tap rows to collect
/// songs (+ turns to ✓), Done adds them all in the order picked.
class SongPickerScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;

  /// When set, Done hands the picked songs to this instead of adding them to
  /// a server playlist (Jam queue, shared playlists). Returns whether it
  /// worked; on false the picker stays open.
  final Future<bool> Function(List<Song> songs)? onPicked;

  const SongPickerScreen({super.key, required this.playlistId, required this.playlistName, this.onPicked});

  /// Picks songs for somewhere other than a Navidrome playlist.
  const SongPickerScreen.custom({super.key, required String destination, required Future<bool> Function(List<Song>) this.onPicked})
      : playlistId = '',
        playlistName = destination;

  @override
  ConsumerState<SongPickerScreen> createState() => _SongPickerScreenState();
}

class _SongPickerScreenState extends ConsumerState<SongPickerScreen> {
  static const _debounce = Duration(milliseconds: 250);

  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  String _query = '';

  /// Picked songs, in the order they were tapped.
  final List<String> _picked = [];
  bool _saving = false;

  PaginatedSongsParam get _param => PaginatedSongsParam(filter: LibraryFilter.allSongs, searchQuery: _query);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(paginatedSongsProvider(_param).notifier).loadNextPage();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  final Map<String, Song> _pickedSongs = {};

  void _toggle(Song s) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_picked.remove(s.id)) {
        _pickedSongs.remove(s.id);
      } else {
        _picked.add(s.id);
        _pickedSongs[s.id] = s;
      }
    });
  }

  Future<void> _done() async {
    if (_picked.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    final onPicked = widget.onPicked;
    if (onPicked != null) {
      final ok = await onPicked([for (final id in _picked) _pickedSongs[id]!]);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _saving = false);
      }
      return;
    }
    final svc = ref.read(subsonicServiceProvider);
    // The page under this sheet shows the confirmation once it closes.
    final page = Navigator.of(context).context;
    var added = 0;
    try {
      for (final id in _picked) {
        await svc.updatePlaylist(widget.playlistId, songIdToAdd: id);
        added++;
      }
      ref.invalidate(songsInPlaylistProvider(widget.playlistId));
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      if (page.mounted) {
        showToast(page, added == 1 ? 'Added 1 song to ${widget.playlistName}' : 'Added $added songs to ${widget.playlistName}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, added == 0 ? 'Couldn’t add songs. Try again.' : 'Added $added of ${_picked.length}. Try the rest again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final page = ref.watch(paginatedSongsProvider(_param));
    final svc = ref.read(subsonicServiceProvider);
    final songs = page.songs;

    return Scaffold(
      backgroundColor: t.bgBase,
      appBar: AppBar(
        backgroundColor: t.bgBase,
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: Space.lg),
          onPressed: () => Navigator.of(context).pop(false),
          child: Align(alignment: Alignment.centerLeft, child: Text('Cancel', style: t.body.copyWith(color: t.accent))),
        ),
        title: Text('Add Songs', style: t.headline),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: Space.xl), child: CupertinoActivityIndicator())
              : CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  onPressed: _done,
                  child: Text(
                    _picked.isEmpty ? 'Done' : 'Add ${_picked.length}',
                    style: t.headline.copyWith(color: t.accent),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
            child: NaviSearchField(
              controller: _search,
              placeholder: 'Search your library',
              onChanged: (v) {
                _timer?.cancel();
                _timer = Timer(_debounce, () => setState(() => _query = v.trim()));
              },
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? (page.isLoadingMore
                    ? const LoadingState()
                    : MessageState(
                        icon: CupertinoIcons.search,
                        title: _query.isEmpty ? 'No songs yet' : 'No songs match “$_query”',
                        message: _query.isEmpty
                            ? 'Songs appear here once your library syncs.'
                            : 'Try a song or artist name.',
                      ))
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: 60,
                    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xl),
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final s = songs[i];
                      final picked = _picked.contains(s.id);
                      return InkWell(
                        onTap: () => _toggle(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                          child: Row(
                            children: [
                              CoverArt(url: svc.getCoverArtUrl(s.coverArt), size: 46, radius: Radii.thumb),
                              const SizedBox(width: Space.md),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                                    Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                                  ],
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: Motion.fast,
                                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                child: Icon(
                                  picked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.add_circled,
                                  key: ValueKey(picked),
                                  size: 26,
                                  color: picked ? t.accent : t.textSecondary,
                                  semanticLabel: picked ? 'Selected' : 'Add',
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
      ),
    );
  }
}
