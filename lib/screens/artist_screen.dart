import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/album.dart';
import '../player/artwork.dart' show coverPaletteProvider;
import '../models/song.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/artwork_page.dart';
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

/// Apple Music artist page: the portrait full-bleed with the name over it,
/// Play/Shuffle across everything they made, the latest release, Top Songs
/// and the discography.
class ArtistScreen extends ConsumerWidget {
  final String artistId;
  final String name;
  const ArtistScreen({super.key, required this.artistId, required this.name});

  Future<void> _play(WidgetRef ref, List<Album> albums, {required bool shuffle}) async {
    final svc = ref.read(subsonicServiceProvider);
    final lists = await Future.wait(albums.map((a) => svc.getAlbum(a.id)));
    final songs = [for (final l in lists) ...l];
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
    final albums = page.asData?.value.albums ?? const <Album>[];
    final top = page.asData?.value.top ?? const <Song>[];
    final latest = albums.isEmpty ? null : albums.first; // sorted newest first
    final fallbackCover = latest == null ? null : svc.getCoverArtUrl(latest.coverArt);
    // Sample the colour from whatever image is shown: the portrait when the
    // server has one, otherwise the newest cover (which CoverArt falls back to).
    final portraitId = 'ar-$artistId';
    final portrait = ref.watch(coverPaletteProvider(portraitId)).asData?.value;
    final hasPortrait = portrait != null && portrait != AlbumPalette.fallback;

    Future<List<Song>> allSongs() async {
      final lists = await Future.wait(albums.map((a) => svc.getAlbum(a.id)));
      return [for (final l in lists) ...l];
    }

    return ArtworkPage(
      paletteCoverId: hasPortrait ? portraitId : latest?.coverArt,
      artistStyle: true,
      art: (size) => CoverArt(
        url: svc.getCoverArtUrl('ar-$artistId'),
        fallbackUrl: fallbackCover,
        size: size,
        radius: 0,
        placeholderIcon: CupertinoIcons.person_fill,
      ),
      title: name,
      detail: albums.isEmpty ? null : (albums.length == 1 ? '1 album' : '${albums.length} albums'),
      buttons: PlayShuffleButtons(
        onPlay: albums.isEmpty ? null : () => _play(ref, albums, shuffle: false),
        onShuffle: albums.isEmpty ? null : () => _play(ref, albums, shuffle: true),
        trailing: CircleIconButton(
          icon: CupertinoIcons.ellipsis,
          label: 'More',
          onTap: albums.isEmpty
              ? null
              : () => showCollectionActions(
                    context,
                    title: name,
                    subtitle: albums.length == 1 ? '1 album' : '${albums.length} albums',
                    artUrl: svc.getCoverArtUrl(hasPortrait ? portraitId : latest?.coverArt),
                    placeholderIcon: CupertinoIcons.person_fill,
                    loadSongs: allSongs,
                    pin: Pin.artist(artistId, name),
                  ),
        ),
      ),
      onRefresh: () async => ref.invalidate(artistPageProvider(key)),
      slivers: page.when(
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
          if (latest != null) SliverToBoxAdapter(child: _LatestRelease(album: latest)),
          if (top.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'Top Songs')),
            SliverFixedExtentList(
              itemExtent: SongTile.extent,
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: top[i],
                  onTap: () => ref.read(playerProvider.notifier).setQueue(top.take(5).toList(), i, playlistName: name),
                ),
                childCount: top.length.clamp(0, 5),
              ),
            ),
          ],
          if (albums.length > 1)
            SliverToBoxAdapter(
              child: MediaShelf(
                title: 'Albums',
                itemCount: albums.length,
                itemBuilder: (context, i) {
                  final a = albums[i];
                  final art = svc.getCoverArtUrl(a.coverArt);
                  return MediaCard(
                    title: a.name,
                    subtitle: a.year > 0 ? '${a.year}' : null,
                    artUrl: art,
                    size: 150,
                    placeholderIcon: CupertinoIcons.music_albums,
                    onTap: () => navigateInApp(context, AlbumDetailsScreen(album: a)),
                    onLongPress: () => showCollectionActions(
                      context,
                      title: a.name,
                      subtitle: name,
                      artUrl: art,
                      placeholderIcon: CupertinoIcons.music_albums,
                      loadSongs: () => svc.getAlbum(a.id),
                      pin: Pin.album(a),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// "Latest Release" card: cover, the release date line, name, track count.
class _LatestRelease extends ConsumerWidget {
  final Album album;
  const _LatestRelease({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
      child: CupertinoClickable(
        onTap: () => navigateInApp(context, AlbumDetailsScreen(album: album)),
        scaleFactor: 0.98,
        semanticLabel: 'Latest release, ${album.name}',
        child: Row(
          children: [
            CoverArt(
              url: ref.read(subsonicServiceProvider).getCoverArtUrl(album.coverArt),
              size: 96,
              radius: Radii.cover,
              placeholderIcon: CupertinoIcons.music_albums,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.year > 0 ? 'Latest Release · ${album.year}' : 'Latest Release', style: t.caption1),
                  const SizedBox(height: Space.xxs),
                  Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headline),
                  const SizedBox(height: Space.xxs),
                  Text(album.songCount == 1 ? '1 song' : '${album.songCount} songs', style: t.footnote),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}
