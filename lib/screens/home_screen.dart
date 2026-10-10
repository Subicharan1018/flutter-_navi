import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/mosaic_art.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';
import 'favorites_screen.dart';
import 'library/albums_page.dart';
import 'library/playlists_page.dart';
import 'navivibe_replay_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';

/// Apple Music's Home: Top Picks as tall feature cards, then shelves of what
/// you played, what you made and what just arrived on the server.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LargeTitlePage(
      title: 'Home',
      trailing: PlatformUtils.isDesktop
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => navigateInApp(context, const SettingsScreen()),
              child: const Icon(CupertinoIcons.person_crop_circle, size: 28, semanticLabel: 'Settings'),
            ),
      onRefresh: () async {
        ref.invalidate(playlistsProvider);
        ref.invalidate(recentlyPlayedAlbumsProvider);
        ref.invalidate(recentlyPlayedSongsProvider);
        ref.invalidate(recentlyAddedAlbumsProvider);
        ref.invalidate(favoritesProvider);
      },
      slivers: const [
        SliverToBoxAdapter(child: _TopPicks()),
        SliverToBoxAdapter(child: _RecentlyPlayed()),
        SliverToBoxAdapter(child: _YourPlaylists()),
        SliverToBoxAdapter(child: _RecentlyAdded()),
        SliverToBoxAdapter(child: _FirstRun()),
      ],
    );
  }
}

String? _art(WidgetRef ref, String? id) =>
    (id == null || id.isEmpty) ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(id);

// ─────────────────────────────────────────────────────────────────────────────
// Top Picks
// ─────────────────────────────────────────────────────────────────────────────

class _TopPicks extends ConsumerWidget {
  const _TopPicks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyPlayedSongsProvider).asData?.value ?? const <Song>[];
    final albums = ref.watch(recentlyPlayedAlbumsProvider).asData?.value ?? const <Album>[];
    final starred = ref.watch(favoritesProvider).asData?.value.songs ?? const <Song>[];

    final mixArt = [
      for (final a in albums.take(8)) _art(ref, a.coverArt),
      for (final s in recent.take(8)) _art(ref, s.coverArt),
    ];
    final favArt = [for (final s in starred.take(12)) _art(ref, s.coverArt)];
    final year = DateTime.now().year;

    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width * 0.62).clamp(200.0, 280.0);

    final cards = <Widget>[
      _FeatureCard(
        eyebrow: 'Made for You',
        title: 'Smart Shuffle',
        subtitle: 'A mix tuned to the time of day and what you play most.',
        art: MosaicArt(urls: mixArt, size: cardWidth, radius: 0, placeholderIcon: CupertinoIcons.sparkles),
        width: cardWidth,
        onTap: () => navigateInApp(context, const AiShuffleScreen()),
      ),
      _FeatureCard(
        eyebrow: 'Your Collection',
        title: 'Favorites',
        subtitle: starred.isEmpty ? 'Star songs to collect them here.' : songCount(starred.length),
        art: MosaicArt(urls: favArt, size: cardWidth, radius: 0, placeholderIcon: CupertinoIcons.star_fill),
        width: cardWidth,
        onTap: () => navigateInApp(context, const FavoritesScreen()),
      ),
      _FeatureCard(
        eyebrow: 'Your Year',
        title: 'Replay $year',
        subtitle: 'Your top songs, artists and listening time.',
        art: _ReplayArt(year: year, size: cardWidth),
        width: cardWidth,
        onTap: () => navigateInApp(context, const NavivibeReplayScreen()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Top Picks for You',
          padding: EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
        ),
        SizedBox(
          height: cardWidth + _FeatureCard.chrome,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }
}

/// Tall Top Picks card: a small caption, then square art sitting on a solid
/// panel with the title and a one-line reason it's here.
class _FeatureCard extends StatelessWidget {
  /// Height added to the art: caption line + text panel.
  static const double chrome = 112;

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget art;
  final double width;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.art,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.98,
      semanticLabel: '$title. $subtitle',
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eyebrow, style: t.footnote),
            const SizedBox(height: Space.xs + 2),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.hero),
                child: ColoredBox(
                  color: t.bgSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      art,
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm + 2, Space.md, Space.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headline),
                              const SizedBox(height: Space.xxs),
                              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replay's art is typographic: the year, set big, on the accent.
class _ReplayArt extends StatelessWidget {
  final int year;
  final double size;
  const _ReplayArt({required this.year, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: size,
      height: size,
      color: t.accent,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Replay', style: t.title3.copyWith(color: t.onAccent)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$year',
              style: t.largeTitle.copyWith(color: t.onAccent, fontSize: size * 0.34, height: 1, letterSpacing: -2),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shelves
// ─────────────────────────────────────────────────────────────────────────────

/// Server's recently played albums; falls back to songs played on this device
/// when the server has none yet.
class _RecentlyPlayed extends ConsumerWidget {
  const _RecentlyPlayed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(recentlyPlayedAlbumsProvider).asData?.value ?? const <Album>[];
    if (albums.isNotEmpty) {
      return MediaShelf(
        title: 'Recently Played',
        itemCount: albums.length.clamp(0, 15),
        itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
      );
    }
    final songs = ref.watch(recentlyPlayedSongsProvider).asData?.value ?? const <Song>[];
    final shown = songs.take(15).toList();
    return MediaShelf(
      title: 'Recently Played',
      itemCount: shown.length,
      itemBuilder: (context, i) => MediaCard(
        title: shown[i].title,
        subtitle: shown[i].artist,
        artUrl: _art(ref, shown[i].coverArt),
        size: 150,
        onTap: () => ref.read(playerProvider.notifier).setQueue(shown, i, playlistName: 'Recently Played'),
      ),
    );
  }
}

class _YourPlaylists extends ConsumerWidget {
  const _YourPlaylists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).asData?.value ?? const <Playlist>[];
    return MediaShelf(
      title: 'Your Playlists',
      onSeeAll: () => navigateInApp(context, const PlaylistsPage()),
      itemCount: playlists.length.clamp(0, 15),
      itemBuilder: (context, i) {
        final p = playlists[i];
        return MediaCard(
          title: p.name,
          subtitle: songCount(p.songCount),
          artUrl: _art(ref, p.coverArt),
          size: 150,
          placeholderIcon: CupertinoIcons.music_note_list,
          onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p)),
          onLongPress: () => showCollectionActions(
            context,
            title: p.name,
            subtitle: songCount(p.songCount),
            artUrl: _art(ref, p.coverArt),
            placeholderIcon: CupertinoIcons.music_note_list,
            loadSongs: () => ref.read(subsonicServiceProvider).getPlaylistSongs(p.id),
          ),
        );
      },
    );
  }
}

class _RecentlyAdded extends ConsumerWidget {
  const _RecentlyAdded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(recentlyAddedAlbumsProvider).asData?.value ?? const <Album>[];
    return MediaShelf(
      title: 'Recently Added',
      onSeeAll: () => navigateInApp(context, const AlbumsPage()),
      itemCount: albums.length.clamp(0, 15),
      itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  final Album album;
  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = _art(ref, album.coverArt);
    return MediaCard(
      title: album.name,
      subtitle: album.artist,
      artUrl: art,
      size: 150,
      placeholderIcon: CupertinoIcons.music_albums,
      onTap: () => navigateInApp(context, AlbumDetailsScreen(album: album)),
      onLongPress: () => showCollectionActions(
        context,
        title: album.name,
        subtitle: album.artist,
        artUrl: art,
        placeholderIcon: CupertinoIcons.music_albums,
        loadSongs: () => ref.read(subsonicServiceProvider).getAlbum(album.id),
      ),
    );
  }
}

/// Shown only when every shelf is empty: a brand-new server or account.
class _FirstRun extends ConsumerWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = (ref.watch(recentlyPlayedAlbumsProvider).asData?.value.isEmpty ?? false) &&
        (ref.watch(recentlyPlayedSongsProvider).asData?.value.isEmpty ?? false) &&
        (ref.watch(playlistsProvider).asData?.value.isEmpty ?? false) &&
        (ref.watch(recentlyAddedAlbumsProvider).asData?.value.isEmpty ?? false);
    if (!empty) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: Space.huge),
      child: MessageState(
        icon: CupertinoIcons.music_house,
        title: 'Your music will show up here',
        message: 'Play an album or make a playlist and Home fills in with what you listen to.',
      ),
    );
  }
}
