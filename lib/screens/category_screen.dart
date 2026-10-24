import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/catalog.dart';
import '../models/song.dart';
import '../providers/catalog_provider.dart';
import '../providers/player_provider.dart';
import '../utils/queue_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import '../widgets/ui/swipe_actions.dart';

/// Every song in one language, the multilingual set, or one genre — with
/// Play and Shuffle across all of them.
class CategoryScreen extends ConsumerWidget {
  final CatalogCategory category;
  const CategoryScreen({super.key, required this.category});

  void _play(WidgetRef ref, List<Song> songs, {int index = 0, bool shuffle = false}) {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(songs, shuffle: true, playlistName: category.name)
        : n.setQueue(songs, index, playlistName: category.name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(categorySongsProvider(category));

    return LargeTitlePage(
      title: category.name,
      onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
      slivers: songs.when(
        loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState.error(
              title: 'Couldn’t load ${category.name}',
              onRetry: () => ref.read(catalogProvider.notifier).refresh(),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: CupertinoIcons.music_note_list,
                    title: 'Nothing here yet',
                    message: 'Songs appear here once your library has synced.',
                  ),
                ),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: PlayShuffleButtons(
                        onPlay: () => _play(ref, list),
                        onShuffle: () => _play(ref, list, shuffle: true),
                      ),
                    ),
                  ),
                ),
                SliverFixedExtentList(
                  itemExtent: SongTile.extent,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SwipeActions.queue(
                      rowKey: ValueKey('cat_${list[i].id}'),
                      context: context,
                      onPlayNext: () => queueSongs(context, ref, [list[i]], next: true),
                      onPlayLast: () => queueSongs(context, ref, [list[i]], next: false),
                      child: SongTile(song: list[i], onTap: () => _play(ref, list, index: i)),
                    ),
                    childCount: list.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Center(
                      child: Text(
                        list.length == 1 ? '1 song' : '${list.length} songs',
                        style: ThemeTokens.of(context).footnote,
                      ),
                    ),
                  ),
                ),
              ],
      ),
    );
  }
}
