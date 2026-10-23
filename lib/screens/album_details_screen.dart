import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/platform_utils.dart';
import '../utils/queue_actions.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/artwork_page.dart';
import '../widgets/ui/collection_hero.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import '../widgets/ui/swipe_actions.dart';
import 'artist_screen.dart';

/// The album's full record and tracks. Keyed by id so the page can open from
/// a song that only knows the album's id and name.
final albumPageProvider = FutureProvider.autoDispose
    .family<({Album album, List<Song> songs}), String>((ref, id) {
  return ref.watch(subsonicServiceProvider).getAlbumDetails(id);
});

/// Other albums by the same artist, for the "More by" shelf.
final moreByArtistProvider = FutureProvider.autoDispose.family<List<Album>, String>((ref, artistId) {
  if (artistId.isEmpty) return const <Album>[];
  return ref.watch(subsonicServiceProvider).getArtistAlbums(artistId);
});

class AlbumDetailsScreen extends ConsumerWidget {
  final Album album;
  const AlbumDetailsScreen({super.key, required this.album});

  /// "Electronic · 2011 · Lossless" — genre, year and, when every track is
  /// lossless, the badge Apple Music shows under the title.
  static String _detail(Album a, List<Song> songs) {
    const lossless = {'flac', 'alac', 'wav', 'aiff', 'ape', 'wv'};
    final allLossless = songs.isNotEmpty && songs.every((s) => lossless.contains(s.suffix.toLowerCase()));
    return [a.detailLine, if (allLossless) 'Lossless'].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(albumPageProvider(album.id));
    // The passed-in album paints at once; the fetched record fills in year,
    // genre and the artist link.
    final full = page.asData?.value.album ?? album;
    final songs = page.asData?.value.songs ?? const <Song>[];
    final svc = ref.read(subsonicServiceProvider);
    final art = svc.getCoverArtUrl(album.coverArt);
    final playingThis = ref.watch(playerProvider.select((s) =>
        s.isPlaying && s.currentSong != null && s.currentSong!.albumId == album.id));

    Future<void> play({int from = 0, bool shuffle = false}) async {
      if (songs.isEmpty) return;
      final n = ref.read(playerProvider.notifier);
      if (playingThis && !shuffle && from == 0) return n.player.pause();
      shuffle
          ? await n.playPlaylist(songs, shuffle: true, playlistName: full.name)
          : await n.setQueue(songs, from, playlistName: full.name, unshuffledSongs: songs);
    }

    void openArtist() => navigateInApp(context, ArtistScreen(artistId: full.artistId, name: full.artist));

    return ArtworkPage(
      paletteCoverId: album.coverArt,
      art: (size) => CoverArt(url: art, size: size, radius: 0, placeholderIcon: CupertinoIcons.music_albums),
      title: full.name,
      subtitle: full.artist,
      onSubtitleTap: full.artistId.isEmpty ? null : openArtist,
      detail: _detail(full, songs),
      buttons: PlayShuffleButtons(
        playing: playingThis,
        onPlay: songs.isEmpty ? null : () => play(),
        onShuffle: songs.isEmpty ? null : () => play(shuffle: true),
        trailing: CollectionDownloadButton(songs: songs),
      ),
      actions: [
        BarCircleButton(
          icon: CupertinoIcons.ellipsis,
          label: 'More',
          onTap: () => showCollectionActions(
            context,
            title: full.name,
            subtitle: full.artist,
            artUrl: art,
            placeholderIcon: CupertinoIcons.music_albums,
            loadSongs: () async => songs,
            pin: Pin.album(full),
          ),
        ),
      ],
      onRefresh: () async => ref.invalidate(albumPageProvider(album.id)),
      slivers: [
        ...page.when(
          loading: () => const [SliverToBoxAdapter(child: TrackListSkeleton(artwork: false))],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(
                title: 'Couldn’t load this album',
                onRetry: () => ref.invalidate(albumPageProvider(album.id)),
              ),
            ),
          ],
          data: (_) => [
            SliverFixedExtentList(
              itemExtent: SongTile.extent,
              delegate: SliverChildBuilderDelegate(
                (context, i) => SwipeActions.queue(
                  rowKey: ValueKey('album_${songs[i].id}'),
                  context: context,
                  onPlayNext: () => queueSongs(context, ref, [songs[i]], next: true),
                  onPlayLast: () => queueSongs(context, ref, [songs[i]], next: false),
                  child: SongTile(
                    song: songs[i],
                    showArtwork: false,
                    showArtist: songs[i].composer.isNotEmpty || songs[i].artist != full.artist,
                    trackNumber: songs[i].track > 0 ? songs[i].track : i + 1,
                    showDuration: PlatformUtils.isDesktop,
                    onTap: () => play(from: i),
                  ),
                ),
                childCount: songs.length,
              ),
            ),
            SliverToBoxAdapter(child: CollectionSummary(songs: songs)),
            SliverToBoxAdapter(child: _MoreByArtist(album: full, onSeeAll: openArtist)),
          ],
        ),
      ],
    );
  }
}

class _MoreByArtist extends ConsumerWidget {
  final Album album;
  final VoidCallback onSeeAll;
  const _MoreByArtist({required this.album, required this.onSeeAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = (ref.watch(moreByArtistProvider(album.artistId)).asData?.value ?? const <Album>[])
        .where((a) => a.id != album.id)
        .toList();
    final svc = ref.read(subsonicServiceProvider);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: MediaShelf(
        title: 'More by ${album.artist}',
        onSeeAll: onSeeAll,
        itemCount: others.length,
        itemBuilder: (context, i) => MediaCard(
          title: others[i].name,
          subtitle: others[i].year > 0 ? '${others[i].year}' : null,
          artUrl: svc.getCoverArtUrl(others[i].coverArt),
          size: 150,
          placeholderIcon: CupertinoIcons.music_albums,
          onTap: () => navigateInApp(context, AlbumDetailsScreen(album: others[i])),
        ),
      ),
    );
  }
}
