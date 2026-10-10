import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/collection_hero.dart';
import '../widgets/ui/detail_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';

/// An artist's albums (keyed by id) and the server's top songs for them.
final artistPageProvider = FutureProvider.autoDispose
    .family<({List<Album> albums, List<Song> top}), ({String id, String name})>((ref, a) async {
  final svc = ref.watch(subsonicServiceProvider);
  final albums = await svc.getArtistAlbums(a.id);
  // Top songs need Last.fm on the server; an artist page without them is fine.
  final top = await svc.getTopSongs(a.name).catchError((_) => <Song>[]);
  return (albums: albums, top: top);
});

/// Apple Music artist page: round portrait, Play/Shuffle over everything they
/// made, Top Songs, then the discography as a grid.
class ArtistScreen extends ConsumerWidget {
  final String artistId;
  final String name;
  const ArtistScreen({super.key, required this.artistId, required this.name});

  Future<List<Song>> _allSongs(WidgetRef ref, List<Album> albums) async {
    final svc = ref.read(subsonicServiceProvider);
    final lists = await Future.wait(albums.map((a) => svc.getAlbum(a.id)));
    return [for (final l in lists) ...l];
  }

  Future<void> _play(WidgetRef ref, List<Album> albums, {required bool shuffle}) async {
    final songs = await _allSongs(ref, albums);
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? await n.playPlaylist(songs, shuffle: true, playlistName: name)
        : await n.setQueue(songs, 0, playlistName: name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: artistId, name: name);
    final page = ref.watch(artistPageProvider(key));
    final svc = ref.read(subsonicServiceProvider);
    final data = page.asData?.value;
    final albums = data?.albums ?? const <Album>[];
    final top = data?.top ?? const <Song>[];

    return DetailPage(
      title: name,
      revealAt: CollectionHero.revealOffset(context),
      onRefresh: () async => ref.invalidate(artistPageProvider(key)),
      slivers: [
        SliverToBoxAdapter(
          child: CollectionHero(
            title: name,
            detail: albums.isEmpty ? null : (albums.length == 1 ? '1 album' : '${albums.length} albums'),
            artUrl: svc.getCoverArtUrl('ar-$artistId'),
            circularArt: true,
            placeholderIcon: CupertinoIcons.person_fill,
            onPlay: albums.isEmpty ? null : () => _play(ref, albums, shuffle: false),
            onShuffle: albums.isEmpty ? null : () => _play(ref, albums, shuffle: true),
          ),
        ),
        ...page.when(
          loading: () => const [SliverToBoxAdapter(child: TrackListSkeleton(rows: 5))],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(
                title: 'Couldn’t load $name',
                onRetry: () => ref.invalidate(artistPageProvider(key)),
              ),
            ),
          ],
          data: (_) => [
            if (top.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Top Songs')),
              SliverFixedExtentList(
                itemExtent: SongTile.extent,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => SongTile(
                    song: top[i],
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .setQueue(top.take(5).toList(), i, playlistName: name),
                  ),
                  childCount: top.length.clamp(0, 5),
                ),
              ),
            ],
            if (albums.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Albums')),
              MediaGrid(
                itemCount: albums.length,
                itemBuilder: (context, i, size) {
                  final a = albums[i];
                  final art = svc.getCoverArtUrl(a.coverArt);
                  return MediaCard(
                    title: a.name,
                    subtitle: a.year > 0 ? '${a.year}' : null,
                    artUrl: art,
                    size: size,
                    placeholderIcon: CupertinoIcons.music_albums,
                    onTap: () => navigateInApp(context, AlbumDetailsScreen(album: a)),
                    onLongPress: () => showCollectionActions(
                      context,
                      title: a.name,
                      subtitle: name,
                      artUrl: art,
                      placeholderIcon: CupertinoIcons.music_albums,
                      loadSongs: () => svc.getAlbum(a.id),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}
