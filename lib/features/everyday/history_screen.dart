import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/queue_actions.dart';
import '../../widgets/art/navi_icons.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/ui/controls.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/states.dart';
import 'history_logic.dart';
import 'history_providers.dart';
import 'save_as_playlist.dart';

/// R4: everything you have played, newest first, by day and time of day.
/// Search takes song words and time words ("tuesday night"). Tap plays from
/// that song on through the plays that followed it; each stretch can be
/// played, queued or saved as a playlist.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(historyProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _playFrom(List<HistoryEntry> entries, int index, String name) async {
    final songs = playFromHere(entries, index);
    if (songs.isEmpty) return;
    await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyProvider);
    final now = DateTime.now();
    final shown = searchHistory(state.entries, _query, now);
    final days = groupByDay(shown, now);

    return LargeTitlePage(
      title: 'History',
      controller: _scroll,
      header: NaviSearchField(
        controller: _search,
        placeholder: 'Song, artist, or “tuesday night”',
        voice: false,
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
      slivers: [
        if (state.entries.isEmpty && state.loading)
          const SliverToBoxAdapter(child: TrackListSkeleton())
        else if (shown.isEmpty)
          SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.clock,
              title: _query.isEmpty ? 'Nothing played yet' : 'No matches',
              message: _query.isEmpty
                  ? 'Songs you listen to are kept here, so you can find that song again.'
                  : 'Try a different word, or a day like “yesterday”.',
            ),
          )
        else
          for (final day in days) ...[
            SliverToBoxAdapter(child: _DayHeader(label: day.label)),
            for (final part in splitByPart(day))
              SliverMainAxisGroup(slivers: [
                SliverToBoxAdapter(child: _PartHeader(part: part, now: now)),
                SliverFixedExtentList(
                  itemExtent: SongTile.extent,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SongTile(
                      key: ValueKey('h_${part.entries[i].at.millisecondsSinceEpoch}_${part.entries[i].song.id}'),
                      song: part.entries[i].song,
                      onTap: () => _playFrom(part.entries, i, day.label),
                    ),
                    childCount: part.entries.length,
                  ),
                ),
              ]),
          ],
        if (!state.reachedEnd && state.entries.isNotEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.lg), child: LoadingState())),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xs),
      child: Semantics(header: true, child: Text(label, style: t.title2)),
    );
  }
}

class _PartHeader extends ConsumerWidget {
  const _PartHeader({required this.part, required this.now});
  final HistoryPart part;
  final DateTime now;

  List<Song> get _songs => songsInHeardOrder(part.entries);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final name = part.part[0].toUpperCase() + part.part.substring(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.xs, 0),
      child: Row(
        children: [
          Expanded(child: Text(name, style: t.subheadline)),
          IconButton(
            tooltip: 'Play $name in the order heard',
            onPressed: () => ref
                .read(playerProvider.notifier)
                .setQueue(_songs, 0, playlistName: name, unshuffledSongs: _songs),
            icon: NaviIcon(NaviGlyph.play, size: 18, color: t.textSecondary),
          ),
          IconButton(
            tooltip: 'Play $name next',
            onPressed: () => queueSongs(context, ref, _songs, next: true, label: name),
            icon: NaviIcon(NaviGlyph.playNext, size: 18, color: t.textSecondary),
          ),
          IconButton(
            tooltip: 'Make a playlist from $name',
            onPressed: () => savePlaylistFromSongs(
              context,
              ref,
              songs: _songs,
              suggestedName: suggestedPlaylistName(part.entries, now),
              title: 'Make a Playlist',
            ),
            icon: NaviIcon(NaviGlyph.addToPlaylist, size: 18, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
