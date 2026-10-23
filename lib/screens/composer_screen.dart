import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/composer.dart';
import '../models/song.dart';
import '../providers/composer_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/queue_actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/artwork_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import '../widgets/ui/swipe_actions.dart';

/// A composer's page: Play and Shuffle across everything they scored, then
/// their songs grouped by film/album, like the artist page.
class ComposerScreen extends ConsumerWidget {
  /// [nameKey] of the composer.
  final String composerKey;
  final String name;
  const ComposerScreen({super.key, required this.composerKey, required this.name});

  void _play(WidgetRef ref, List<Song> songs, {required bool shuffle}) {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(songs, shuffle: true, playlistName: name)
        : n.setQueue(songs, 0, playlistName: name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composer = ref.watch(composerProvider(composerKey));
    final loading = ref.watch(composersProvider.select((v) => v.isLoading));
    final albums = composer == null ? const <ComposerAlbum>[] : groupByAlbum(composer.songs);
    final ordered = [for (final a in albums) ...a.songs];
    final svc = ref.read(subsonicServiceProvider);
    final cover = ordered.isEmpty ? null : ordered.first.coverArt;

    return ArtworkPage(
      paletteCoverId: cover,
      artistStyle: true,
      art: (size) => CoverArt(
        url: cover == null ? null : svc.getCoverArtUrl(cover),
        size: size,
        radius: 0,
        placeholderIcon: CupertinoIcons.music_mic,
      ),
      title: composer?.name ?? name,
      subtitle: 'Composer',
      detail: composer == null
          ? null
          : '${songCount(composer.songCount)} · ${albums.length == 1 ? '1 film' : '${albums.length} films'}',
      buttons: PlayShuffleButtons(
        onPlay: ordered.isEmpty ? null : () => _play(ref, ordered, shuffle: false),
        onShuffle: ordered.isEmpty ? null : () => _play(ref, ordered, shuffle: true),
      ),
      slivers: composer == null
          ? [
              if (loading)
                const SliverToBoxAdapter(child: TrackListSkeleton(rows: 5))
              else
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: CupertinoIcons.music_mic,
                    title: 'No songs by this composer',
                    message: 'Songs credited to them appear here once the library syncs.',
                  ),
                ),
            ]
          : [
              for (final album in albums) ...[
                SliverToBoxAdapter(child: SectionHeader(title: album.name)),
                SliverFixedExtentList(
                  itemExtent: SongTile.extent,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final song = album.songs[i];
                      return SwipeActions.queue(
                        rowKey: ValueKey('composer_${song.id}'),
                        context: context,
                        onPlayNext: () => queueSongs(context, ref, [song], next: true),
                        onPlayLast: () => queueSongs(context, ref, [song], next: false),
                        child: SongTile(
                          song: song,
                          onTap: () => ref
                              .read(playerProvider.notifier)
                              .setQueue(ordered, ordered.indexOf(song), playlistName: name, unshuffledSongs: ordered),
                        ),
                      );
                    },
                    childCount: album.songs.length,
                  ),
                ),
              ],
            ],
    );
  }
}
