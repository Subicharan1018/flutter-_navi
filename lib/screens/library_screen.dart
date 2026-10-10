import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import 'album_details_screen.dart';
import 'favorites_screen.dart';
import 'library/albums_page.dart';
import 'library/playlists_page.dart';
import 'library/songs_page.dart';

/// Apple Music's Library: destinations up top, Recently Added below.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyAddedAlbumsProvider).asData?.value ?? const [];
    final svc = ref.read(subsonicServiceProvider);

    return LargeTitlePage(
      title: 'Library',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => showDialog(context: context, builder: (_) => const CreatePlaylistDialog()),
        child: const Icon(CupertinoIcons.add, semanticLabel: 'New Playlist'),
      ),
      onRefresh: () async {
        ref.invalidate(recentlyAddedAlbumsProvider);
        ref.invalidate(playlistsProvider);
      },
      slivers: [
        SliverList.list(children: [
          CollectionRow.destination(
            context: context,
            icon: CupertinoIcons.music_note_list,
            title: 'Playlists',
            onTap: () => navigateInApp(context, const PlaylistsPage()),
          ),
          CollectionRow.destination(
            context: context,
            icon: CupertinoIcons.square_stack,
            title: 'Albums',
            onTap: () => navigateInApp(context, const AlbumsPage()),
          ),
          CollectionRow.destination(
            context: context,
            icon: CupertinoIcons.music_note,
            title: 'Songs',
            onTap: () => navigateInApp(context, const SongsPage()),
          ),
          CollectionRow.destination(
            context: context,
            icon: CupertinoIcons.star,
            title: 'Favorites',
            onTap: () => navigateInApp(context, const FavoritesScreen()),
          ),
          CollectionRow.destination(
            context: context,
            icon: CupertinoIcons.arrow_down_circle,
            title: 'Downloaded',
            onTap: () => navigateInApp(context, const SongsPage(downloadedOnly: true)),
          ),
        ]),
        if (recent.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Recently Added')),
          MediaGrid(
            itemCount: recent.length,
            itemBuilder: (context, i, size) {
              final a = recent[i];
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
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
