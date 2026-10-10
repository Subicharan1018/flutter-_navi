import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';

/// Every album in one genre, with a one-tap shuffle across all of them.
class GenreScreen extends ConsumerWidget {
  final String genre;
  const GenreScreen({super.key, required this.genre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(genreAlbumsProvider(genre));
    final svc = ref.read(subsonicServiceProvider);

    return LargeTitlePage(
      title: genre,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: albums.asData?.value.isEmpty ?? true
            ? null
            : () async {
                final lists = await Future.wait(albums.requireValue.take(25).map((a) => svc.getAlbum(a.id)));
                final songs = [for (final l in lists) ...l];
                if (songs.isEmpty) return;
                await ref.read(playerProvider.notifier).playPlaylist(songs, shuffle: true, playlistName: genre);
              },
        child: const Icon(CupertinoIcons.shuffle, semanticLabel: 'Shuffle genre'),
      ),
      onRefresh: () async => ref.invalidate(genreAlbumsProvider(genre)),
      slivers: albums.when(
        loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState.error(
              title: 'Couldn’t load $genre',
              onRetry: () => ref.invalidate(genreAlbumsProvider(genre)),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: CupertinoIcons.music_albums,
                    title: 'No albums in $genre',
                    message: 'Albums tagged with this genre on your server appear here.',
                  ),
                ),
              ]
            : [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                MediaGrid(
                  itemCount: list.length,
                  itemBuilder: (context, i, size) {
                    final a = list[i];
                    final art = svc.getCoverArtUrl(a.coverArt);
                    return MediaCard(
                      title: a.name,
                      subtitle: a.artist,
                      artUrl: art,
                      size: size,
                      placeholderIcon: CupertinoIcons.music_albums,
                      onTap: () => navigateInApp(context, AlbumDetailsScreen(album: a)),
                      onLongPress: () => showCollectionActions(
                        context,
                        title: a.name,
                        subtitle: a.artist,
                        artUrl: art,
                        placeholderIcon: CupertinoIcons.music_albums,
                        loadSongs: () => svc.getAlbum(a.id),
                        pin: Pin.album(a),
                      ),
                    );
                  },
                ),
              ],
      ),
    );
  }
}
