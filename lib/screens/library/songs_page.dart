import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/library_sort.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../utils/queue_actions.dart';
import '../../widgets/song_tile.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../../widgets/ui/swipe_actions.dart';
import 'sort_menu.dart';

/// Every song in the library (or only downloaded ones), paged from the local
/// mirror. Fills in live while the first sync on a new install runs.
class SongsPage extends ConsumerStatefulWidget {
  final bool downloadedOnly;
  const SongsPage({super.key, this.downloadedOnly = false});

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  final _scroll = ScrollController();

  PaginatedSongsParam get _param => PaginatedSongsParam(
        filter: widget.downloadedOnly ? LibraryFilter.downloaded : LibraryFilter.allSongs,
        searchQuery: '',
      );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(paginatedSongsProvider(_param).notifier).loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _play(List<Song> songs, {int index = 0, bool shuffle = false}) {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(songs, shuffle: true, playlistName: 'Songs')
        : n.setQueue(songs, index, playlistName: 'Songs', unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(paginatedSongsProvider(_param));
    final sync = ref.watch(librarySyncProvider);
    final songs = page.songs;

    return LargeTitlePage(
      title: widget.downloadedOnly ? 'Downloaded' : 'Songs',
      controller: _scroll,
      trailing: const SortButton(
        section: LibraryFilter.allSongs,
        fields: [
          LibrarySortField.name,
          LibrarySortField.artistName,
          LibrarySortField.recentlyAdded,
          LibrarySortField.playCount,
          LibrarySortField.duration,
        ],
      ),
      onRefresh: () async => ref.read(paginatedSongsProvider(_param).notifier).loadNextPage(isRefresh: true),
      slivers: [
        if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: page.isLoadingMore || sync.syncing
                ? LoadingState(
                    label: sync.syncing && !widget.downloadedOnly
                        ? 'Getting your library ready… ${sync.synced} songs'
                        : null,
                  )
                : sync.error != null && !widget.downloadedOnly
                    ? MessageState.error(
                        title: 'Couldn’t load your library',
                        onRetry: () => ref.invalidate(allSongsProvider),
                      )
                    : MessageState(
                        illustration: widget.downloadedOnly ? null : 'books',
                        icon: widget.downloadedOnly ? CupertinoIcons.arrow_down_circle : CupertinoIcons.music_note,
                        title: widget.downloadedOnly ? 'No downloads yet' : 'No songs yet',
                        message: widget.downloadedOnly
                            ? 'Download songs from their menu to listen without a connection.'
                            : 'Songs on your server appear here once the library syncs.',
                      ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: PlayShuffleButtons(
                  onPlay: () => _play(songs),
                  onShuffle: () => _play(songs, shuffle: true),
                ),
              ),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) => SwipeActions.queue(
                rowKey: ValueKey('song_${songs[i].id}'),
                context: context,
                onPlayNext: () => queueSongs(context, ref, [songs[i]], next: true),
                onPlayLast: () => queueSongs(context, ref, [songs[i]], next: false),
                child: SongTile(song: songs[i], onTap: () => _play(songs, index: i)),
              ),
              childCount: songs.length,
            ),
          ),
          if (page.isLoadingMore)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.lg), child: CupertinoActivityIndicator())),
        ],
      ],
    );
  }
}
