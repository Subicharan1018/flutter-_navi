import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/album.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/queue_actions.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/artwork_page.dart';
import '../widgets/ui/collection_hero.dart';
import '../widgets/ui/controls.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/mosaic_art.dart';
import '../widgets/ui/states.dart';
import '../widgets/ui/swipe_actions.dart';
import 'album_details_screen.dart';

enum _View { songs, albums }

/// Everything you starred, presented as a playlist: a mosaic of its covers,
/// Play/Shuffle, and a Songs / Albums switch.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  _View _view = _View.songs;

  Future<void> _play(List<Song> songs, {int from = 0, bool shuffle = false}) async {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? await n.playPlaylist(songs, shuffle: true, playlistName: 'Favorites')
        : await n.setQueue(songs, from, playlistName: 'Favorites', unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final songs = favorites.asData?.value.songs ?? const <Song>[];
    final albums = favorites.asData?.value.albums ?? const <Album>[];
    final svc = ref.read(subsonicServiceProvider);

    return ArtworkPage(
      paletteCoverId: songs.isEmpty ? null : songs.first.coverArt,
      art: (size) => MosaicArt(
        urls: [for (final s in songs.take(24)) svc.getCoverArtUrl(s.coverArt)],
        size: size,
        radius: 0,
        placeholderIcon: NaviGlyph.star,
        seed: coverSeed('Favorites'),
      ),
      title: 'Favorites',
      detail: favorites.hasValue
          ? '${songCount(songs.length)} · ${albums.length == 1 ? '1 album' : '${albums.length} albums'}'
          : null,
      buttons: PlayShuffleButtons(
        onPlay: songs.isEmpty ? null : () => _play(songs),
        onShuffle: songs.isEmpty ? null : () => _play(songs, shuffle: true),
        trailing: CollectionDownloadButton(songs: songs),
      ),
      onRefresh: () async => ref.invalidate(favoritesProvider),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
          sliver: SliverToBoxAdapter(
            child: NaviSegmented<_View>(
              segments: const {_View.songs: 'Songs', _View.albums: 'Albums'},
              value: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
          ),
        ),
        ...favorites.when(
          loading: () => const [SliverToBoxAdapter(child: TrackListSkeleton())],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(
                title: 'Couldn’t load your favorites',
                onRetry: () => ref.invalidate(favoritesProvider),
              ),
            ),
          ],
          data: (_) => switch (_view) {
            _View.songs when songs.isEmpty => const [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.star,
                    art: EmptyArtKind.heart,
                    title: 'No favorite songs yet',
                    message: 'Tap the star on any song and it’s collected here.',
                  ),
                ),
              ],
            _View.songs => [
                SliverFixedExtentList(
                  itemExtent: SongTile.extent,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SwipeActions.queue(
                      rowKey: ValueKey('fav_${songs[i].id}'),
                      context: context,
                      onPlayNext: () => queueSongs(context, ref, [songs[i]], next: true),
                      onPlayLast: () => queueSongs(context, ref, [songs[i]], next: false),
                      child: SongTile(song: songs[i], onTap: () => _play(songs, from: i)),
                    ),
                    childCount: songs.length,
                  ),
                ),
                SliverToBoxAdapter(child: CollectionSummary(songs: songs)),
              ],
            _View.albums when albums.isEmpty => const [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.library,
                    art: EmptyArtKind.heart,
                    title: 'No favorite albums yet',
                    message: 'Albums you star on your server appear here.',
                  ),
                ),
              ],
            _View.albums => [
                MediaGrid(
                  itemCount: albums.length,
                  itemBuilder: (context, i, size) {
                    final a = albums[i];
                    final art = svc.getCoverArtUrl(a.coverArt);
                    return MediaCard(
                      title: a.name,
                      subtitle: a.artist,
                      artUrl: art,
                      size: size,
                      placeholderIcon: NaviGlyph.library,
                      onTap: () => navigateInApp(context, AlbumDetailsScreen(album: a)),
                      onLongPress: () => showCollectionActions(
                        context,
                        title: a.name,
                        subtitle: a.artist,
                        artUrl: art,
                        placeholderIcon: NaviGlyph.library,
                        loadSongs: () => svc.getAlbum(a.id),
                        pin: Pin.album(a),
                      ),
                    );
                  },
                ),
              ],
          },
        ),
      ],
    );
  }
}
