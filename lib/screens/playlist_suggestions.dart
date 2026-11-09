import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/cover_art.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/navi_icon_button.dart';

/// "Suggested Songs" under a playlist: library songs that fit it, each with
/// the reason, and a plus that adds the song straight to the playlist.
class PlaylistSuggestions extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;

  /// The playlist's songs now; suggestions are refreshed when this changes.
  final List<Song> songs;

  /// Called after a song was added, so the page can reload its list.
  final VoidCallback onAdded;

  const PlaylistSuggestions({
    super.key,
    required this.playlistId,
    required this.playlistName,
    required this.songs,
    required this.onAdded,
  });

  @override
  ConsumerState<PlaylistSuggestions> createState() => _PlaylistSuggestionsState();
}

typedef _Pick = ({Song song, String why});

class _PlaylistSuggestionsState extends ConsumerState<PlaylistSuggestions> {
  List<_Pick> _picks = const [];
  final _adding = <String>{};
  String _loadedFor = '';

  String get _signature => widget.songs.map((s) => s.id).join(',');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PlaylistSuggestions old) {
    super.didUpdateWidget(old);
    if (_signature != _loadedFor) _load();
  }

  /// Every song suggested so far on this page, so Refresh never repeats one.
  final _seen = <String>{};
  bool _refreshing = false;

  /// A new batch: asks for more than a screenful and shows the first ten that
  /// have not been suggested before (the server has no "exclude" of its own).
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final found = await ref
          .read(shuffleRepositoryProvider)
          .getPlaylistSuggestions(widget.songs.map((s) => s.id).toList(), limit: 60);
      final library = {for (final s in await ref.read(allSongsProvider.future)) s.id: s};
      if (!mounted) return;
      final fresh = <_Pick>[
        for (final f in found)
          if (library[f.id] != null && !_seen.contains(f.id)) (song: library[f.id]!, why: f.why),
      ].take(10).toList();
      if (fresh.isEmpty) {
        showToast(context, 'No new suggestions right now.');
      } else {
        _seen.addAll(fresh.map((p) => p.song.id));
        setState(() => _picks = fresh);
      }
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t get new suggestions. Try again.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _load() async {
    final signature = _loadedFor = _signature;
    try {
      final found = await ref
          .read(shuffleRepositoryProvider)
          .getPlaylistSuggestions(widget.songs.map((s) => s.id).toList(), limit: 10);
      final library = {for (final s in await ref.read(allSongsProvider.future)) s.id: s};
      if (!mounted || signature != _loadedFor) return;
      final picks = [
        for (final f in found)
          if (library[f.id] != null) (song: library[f.id]!, why: f.why),
      ];
      _seen.addAll(picks.map((p) => p.song.id));
      setState(() => _picks = picks);
    } catch (_) {
      // Suggestions are a bonus: no server, no section.
      if (mounted && signature == _loadedFor) setState(() => _picks = const []);
    }
  }

  Future<void> _add(_Pick pick) async {
    if (!_adding.add(pick.song.id)) return;
    HapticFeedback.lightImpact();
    setState(() {});
    try {
      final svc = ref.read(subsonicServiceProvider);
      await svc.updatePlaylist(widget.playlistId, songIdToAdd: pick.song.id);
      await svc.invalidatePlaylist(widget.playlistId);
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      setState(() => _picks = [..._picks]..remove(pick));
      showToast(context, 'Added to ${widget.playlistName}');
      widget.onAdded();
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t add “${pick.song.title}”. Try again.');
    } finally {
      _adding.remove(pick.song.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_picks.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader(title: 'Suggested Songs')),
            Padding(
              padding: EdgeInsets.only(right: pageGutter(context), top: Space.xl),
              child: NaviIconButton(
                glyph: NaviGlyph.repeat,
                tooltip: 'Refresh suggestions',
                box: 40,
                onTap: _refreshing ? null : _refresh,
              ),
            ),
          ],
        ),
        for (final pick in _picks)
          InkWell(
            onTap: () => ref.read(playerProvider.notifier).setQueue([pick.song], 0),
            child: SizedBox(
              height: 62,
              child: Row(
                children: [
                  const SizedBox(width: Space.gutter),
                  CoverArt(
                    url: svc.getCoverArtUrl(pick.song.coverArt.isNotEmpty ? pick.song.coverArt : pick.song.id),
                    size: ArtSize.of(context).thumb,
                    radius: Radii.thumb,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pick.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                        Text(
                          pick.why.isEmpty ? pick.song.artist : pick.why,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.subheadline,
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    minimumSize: const Size(52, 52),
                    onPressed: _adding.contains(pick.song.id) ? null : () => _add(pick),
                    child: NaviIcon(NaviGlyph.plusCircle, color: t.accent, semanticLabel: 'Add ${pick.song.title}'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}
