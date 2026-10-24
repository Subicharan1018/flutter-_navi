import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../../widgets/ui/swipe_actions.dart';
import '../logic/local_library_providers.dart';

/// Library > On This Device: songs from the folders added in Settings >
/// Local music that the server doesn't have, ordered artist → album → track.
class LocalSongsPage extends ConsumerWidget {
  const LocalSongsPage({super.key});

  static const _list = 'On this device';

  void _play(WidgetRef ref, List<Song> songs, {int index = 0, bool shuffle = false}) {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(songs, shuffle: true, playlistName: _list)
        : n.setQueue(songs, index, playlistName: _list, unshuffledSongs: songs);
  }

  Future<void> _addFolder(WidgetRef ref) async {
    final folder = await pickLocalFolder();
    if (folder != null) await ref.read(localFoldersProvider.notifier).add(folder);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(localSongsProvider);
    final scan = ref.watch(localScanProvider);
    final folders = ref.watch(localFoldersProvider);
    final songs = songsAsync.asData?.value ?? const <Song>[];

    return LargeTitlePage(
      title: 'On This Device',
      onRefresh: folders.isEmpty ? null : () => ref.read(localScanProvider.notifier).scan(),
      slivers: [
        if (songsAsync.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState.error(
              title: 'Couldn’t load your songs',
              message: 'Close this page and open it again.',
              onRetry: () => ref.invalidate(localSongsProvider),
            ),
          )
        else if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: songsAsync.isLoading || scan.running
                ? LoadingState(
                    label: scan.running && scan.total > 0 ? 'Reading ${scan.done} of ${scan.total} songs…' : null,
                  )
                : MessageState(
                    icon: NaviGlyph.folder,
                    art: EmptyArtKind.record,
                    title: folders.isEmpty ? 'No music folders yet' : 'No songs found',
                    message: folders.isEmpty
                        ? 'Add a folder of songs on this device to play them here, with or without a connection.'
                        : 'Songs in your folders show up here. Pull down to scan again.',
                    actionLabel: 'Add Folder',
                    onAction: () => _addFolder(ref),
                  ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: PlayShuffleButtons(
                  onPlay: () => _play(ref, songs),
                  onShuffle: () => _play(ref, songs, shuffle: true),
                ),
              ),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: SongTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) => SwipeActions.queue(
                rowKey: ValueKey('local_${songs[i].id}'),
                context: context,
                onPlayNext: () => queueSongs(context, ref, [songs[i]], next: true),
                onPlayLast: () => queueSongs(context, ref, [songs[i]], next: false),
                child: SongTile(song: songs[i], onTap: () => _play(ref, songs, index: i)),
              ),
              childCount: songs.length,
            ),
          ),
        ],
      ],
    );
  }
}
