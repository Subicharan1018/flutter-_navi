import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../models/library_sort.dart';
import '../../providers/library_provider.dart';
import '../../providers/pins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/collection_actions.dart';
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../album_details_screen.dart';
import 'sort_menu.dart';

/// All albums as a cover grid.
class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(sortedAlbumsProvider);
    final svc = ref.read(subsonicServiceProvider);

    return LargeTitlePage(
      title: 'Albums',
      trailing: const SortButton(
        section: LibraryFilter.albums,
        fields: [LibrarySortField.name, LibrarySortField.artistName, LibrarySortField.duration],
      ),
      onRefresh: () async => ref.invalidate(libraryAlbumsProvider),
      slivers: [
        ...albums.when(
          loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
          error: (_, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: MessageState.error(title: 'Couldn’t load albums', onRetry: () => ref.invalidate(libraryAlbumsProvider)),
            ),
          ],
          data: (list) => list.isEmpty
              ? const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageState(
                      icon: CupertinoIcons.square_stack,
                      title: 'No albums yet',
                      message: 'Albums on your server appear here.',
                    ),
                  ),
                ]
              : [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  MediaGrid(
                    itemCount: list.length,
                    itemBuilder: (context, i, size) => _AlbumCard(album: list[i], size: size, artUrl: svc.getCoverArtUrl(list[i].coverArt)),
                  ),
                ],
        ),
      ],
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  final Album album;
  final double size;
  final String artUrl;
  const _AlbumCard({required this.album, required this.size, required this.artUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MediaCard(
      title: album.name,
      subtitle: album.artist,
      artUrl: artUrl,
      size: size,
      placeholderIcon: CupertinoIcons.music_albums,
      onTap: () => navigateInApp(context, AlbumDetailsScreen(album: album)),
      onLongPress: () => showCollectionActions(
        context,
        title: album.name,
        subtitle: album.artist,
        artUrl: artUrl,
        placeholderIcon: CupertinoIcons.music_albums,
        loadSongs: () => ref.read(subsonicServiceProvider).getAlbum(album.id),
        pin: Pin.album(album),
      ),
    );
  }
}
