import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/local_library/logic/local_library_providers.dart';
import '../features/local_library/ui/local_songs_page.dart';
import '../features/social/ui/social_screen.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/pins_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/art/navi_icons.dart';
import '../widgets/collection_actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import 'album_details_screen.dart';
import 'artist_screen.dart';
import 'favorites_screen.dart';
import 'library/albums_page.dart';
import 'library/artists_page.dart';
import 'library/playlists_page.dart';
import 'library/songs_page.dart';
import 'playlist_details_screen.dart';
import 'playlist_editor.dart';

/// Apple Music's Library (iOS 26): your pins up top, the sections, then
/// what was recently added to the server.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyAddedAlbumsProvider).asData?.value ?? const <Album>[];
    final pins = ref.watch(pinsProvider);
    final svc = ref.read(subsonicServiceProvider);

    final hasLocal = ref.watch(localFoldersProvider.select((f) => f.isNotEmpty));

    final destinations = <(NaviGlyph, String, Widget)>[
      (NaviGlyph.playlist, 'Playlists', const PlaylistsPage()),
      (NaviGlyph.mic, 'Artists', const ArtistsPage()),
      (NaviGlyph.stack, 'Albums', const AlbumsPage()),
      (NaviGlyph.note, 'Songs', const SongsPage()),
      (NaviGlyph.star, 'Favorites', const FavoritesScreen()),
      (NaviGlyph.downloadCircle, 'Downloaded', const SongsPage(downloadedOnly: true)),
      if (hasLocal) (NaviGlyph.folder, 'On This Device', const LocalSongsPage()),
    ];

    return LargeTitlePage(
      title: 'Library',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => showPlaylistEditor(context),
        child: const NaviIcon(NaviGlyph.plus, semanticLabel: 'New Playlist'),
      ),
      onRefresh: () async {
        ref.invalidate(recentlyAddedAlbumsProvider);
        ref.invalidate(playlistsProvider);
      },
      slivers: [
        if (pins.isNotEmpty) _PinsGrid(pins: pins),
        SliverPadding(
          padding: EdgeInsets.only(top: pins.isEmpty ? 0 : Space.lg),
          sliver: SliverList.list(children: [
            for (final (icon, title, page) in destinations)
              CollectionRow.destination(
                context: context,
                icon: icon,
                title: title,
                onTap: () => navigateInApp(context, page),
              ),
            CollectionRow(
              title: 'Sessions',
              titleStyle: ThemeTokens.of(context).title3.copyWith(fontWeight: FontWeight.w400),
              leading: SizedBox(
                width: 30,
                child: NaviIcon(NaviGlyph.group, size: 26, color: ThemeTokens.of(context).accent),
              ),
              showSeparator: false,
              onTap: () => navigateInApp(context, const SocialScreen()),
            ),
          ]),
        ),
        if (pins.isEmpty)
          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final t = ThemeTokens.of(context);
              return Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
                child: Row(
                  children: [
                    NaviIcon(NaviGlyph.pin, size: 15, color: t.textMuted),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Touch and hold an album, playlist or artist to pin it here.',
                        style: t.footnote,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        if (recent.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: 'Recently Added', onTap: () => navigateInApp(context, const AlbumsPage())),
          ),
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
      ],
    );
  }
}

/// Pinned items as a grid of large tiles, three across (artists round).
class _PinsGrid extends ConsumerWidget {
  final List<Pin> pins;
  const _PinsGrid({required this.pins});

  void _open(BuildContext context, WidgetRef ref, Pin p) {
    switch (p.kind) {
      case PinKind.album:
        navigateInApp(
          context,
          AlbumDetailsScreen(
            album: Album.fromJson({'id': p.id, 'name': p.title, 'artist': p.subtitle, 'coverArt': p.coverArt}),
          ),
        );
      case PinKind.playlist:
        // Prefer the live playlist (name/cover may have changed since pinning).
        final live = ref.read(playlistsProvider).asData?.value.where((e) => e.id == p.id).firstOrNull;
        navigateInApp(
          context,
          PlaylistDetailsScreen(
            playlist: live ??
                Playlist(id: p.id, name: p.title, comment: '', songCount: 0, duration: 0, coverArt: p.coverArt),
          ),
        );
      case PinKind.artist:
        navigateInApp(context, ArtistScreen(artistId: p.id, name: p.title));
    }
  }

  Future<List<Song>> _songs(WidgetRef ref, Pin p) async {
    final svc = ref.read(subsonicServiceProvider);
    switch (p.kind) {
      case PinKind.album:
        return svc.getAlbum(p.id);
      case PinKind.playlist:
        return svc.getPlaylistSongs(p.id);
      case PinKind.artist:
        final albums = await svc.getArtistAlbums(p.id);
        final lists = await Future.wait(albums.map((a) => svc.getAlbum(a.id)));
        return [for (final l in lists) ...l];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(subsonicServiceProvider);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
      sliver: SliverLayoutBuilder(builder: (context, c) {
        final columns = c.crossAxisExtent >= 600 ? 6 : 3;
        final tile = (c.crossAxisExtent - Space.md * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.lg,
            mainAxisExtent: tile + 38,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final p = pins[i];
              final artist = p.kind == PinKind.artist;
              final url = p.coverArt.isEmpty ? null : svc.getCoverArtUrl(p.coverArt);
              return MediaCard(
                title: p.title,
                subtitle: p.subtitle,
                art: CoverArt(
                  url: url,
                  size: tile,
                  radius: Radii.cover,
                  circular: artist,
                  placeholderIcon: switch (p.kind) {
                    PinKind.album => NaviGlyph.library,
                    PinKind.playlist => NaviGlyph.playlist,
                    PinKind.artist => NaviGlyph.person,
                  },
                ),
                size: tile,
                circular: artist,
                onTap: () => _open(context, ref, p),
                onLongPress: () => showCollectionActions(
                  context,
                  title: p.title,
                  subtitle: p.subtitle,
                  artUrl: url,
                  loadSongs: () => _songs(ref, p),
                  pin: p,
                ),
              );
            },
            childCount: pins.length,
          ),
        );
      }),
    );
  }
}
