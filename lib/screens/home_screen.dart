import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../features/discover/logic/discover_providers.dart' show discoverProvider;
import '../features/discover/ui/discover_section.dart';
import '../features/social/ui/jam/jam_hero.dart';
import '../features/updates/ui/update_banner.dart';
import '../features/flow/logic/flow_controller.dart' show flowMoodsProvider;
import '../features/flow/ui/flow_section.dart';
import '../features/trending/logic/trending_providers.dart' show trendingChartsProvider;
import '../features/weekly_mix/logic/weekly_mix_providers.dart' show weeklyMixProvider;
import '../features/weekly_mix/ui/weekly_mix_section.dart';
import '../features/trending/ui/trending_section.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../player/artwork.dart' show coverPaletteProvider;
import '../providers/library_provider.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/format.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/ui/action_sheet.dart' show showToast;
import '../widgets/ui/large_title_page.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/mosaic_art.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';
import 'favorites_screen.dart';
import 'library/albums_page.dart';
import 'library/playlists_page.dart';
import 'replay/replay_screen.dart';
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
              child: const NaviIcon(NaviGlyph.personCircle, size: 28, semanticLabel: 'Settings'),
            ),
      onRefresh: () async {
        ref.invalidate(playlistsProvider);
        ref.invalidate(recentlyPlayedAlbumsProvider);
        ref.invalidate(recentlyPlayedSongsProvider);
        ref.invalidate(recentlyAddedAlbumsProvider);
        ref.invalidate(favoritesProvider);
        ref.invalidate(trendingChartsProvider);
        ref.invalidate(discoverProvider);
        ref.invalidate(weeklyMixProvider);
        ref.invalidate(flowMoodsProvider);
      },
      slivers: const [
        SliverToBoxAdapter(child: UpdateBanner()),
        SliverToBoxAdapter(child: JamHero()),
        // What's new leads; the charts it came from right below.
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 1, child: DiscoverSection())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 2, child: WeeklyMixSection())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 3, child: FlowSection())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 4, child: TrendingSection())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 5, child: _TopPicks())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 6, child: _RecentlyPlayed())),
        SliverToBoxAdapter(child: Entrance(group: 'home', index: 7, child: _YourPlaylists())),
        SliverToBoxAdapter(child: _RecentlyAdded()),
        SliverToBoxAdapter(child: _FirstRun()),
      ],
    );
  }
}

/// Cover size on Home's shelves: a step up from Library grids, as on
/// Apple Music's Home.
const double _shelfCover = 164;

String? _art(WidgetRef ref, String? id) =>
    (id == null || id.isEmpty) ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(id);

// ─────────────────────────────────────────────────────────────────────────────
// Top Picks
// ─────────────────────────────────────────────────────────────────────────────

class _TopPicks extends ConsumerWidget {
  const _TopPicks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentlyPlayedSongsProvider);
    final albumsAsync = ref.watch(recentlyPlayedAlbumsProvider);
    final recent = recentAsync.asData?.value ?? const <Song>[];
    final albums = albumsAsync.asData?.value ?? const <Album>[];
    final added = ref.watch(recentlyAddedAlbumsProvider).asData?.value ?? const <Album>[];
    final starred = ref.watch(favoritesProvider).asData?.value.songs ?? const <Song>[];

    // A listener with no history yet: lead with the one tap that plays music.
    final newListener = recentAsync.hasValue && albumsAsync.hasValue && recent.isEmpty && albums.isEmpty;

    final mixArt = [
      for (final a in albums.take(8)) _art(ref, a.coverArt),
      for (final s in recent.take(8)) _art(ref, s.coverArt),
    ];
    final favArt = [for (final s in starred.take(12)) _art(ref, s.coverArt)];
    final year = DateTime.now().year;

    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width * 0.7).clamp(220.0, 300.0);

    final cards = <Widget>[
      if (newListener)
        _FeatureCard(
          title: 'Start Listening',
          subtitle: 'A shuffle of everything in the library. Tap to play.',
          art: MosaicArt(
            urls: [for (final a in added.take(8)) _art(ref, a.coverArt)],
            size: cardWidth,
            radius: 0,
            placeholderIcon: NaviGlyph.shuffle,
            seed: coverSeed('Start Listening'),
          ),
          paletteCoverId: added.isEmpty ? null : added.first.coverArt,
          width: cardWidth,
          onTap: () => _shuffleLibrary(context, ref),
          onPlay: () => _shuffleLibrary(context, ref),
        ),
      _FeatureCard(
        title: 'Smart Shuffle',
        subtitle: 'A mix tuned to the time of day and what you play most.',
        art: MosaicArt(urls: mixArt, size: cardWidth, radius: 0, placeholderIcon: NaviGlyph.signal, seed: coverSeed('Smart Shuffle')),
        paletteCoverId: albums.isNotEmpty ? albums.first.coverArt : (recent.isNotEmpty ? recent.first.coverArt : null),
        width: cardWidth,
        onTap: () => navigateInApp(context, const AiShuffleScreen()),
      ),
      _FeatureCard(
        title: 'Favorites',
        subtitle: starred.isEmpty ? 'Star songs to collect them here.' : songCount(starred.length),
        art: MosaicArt(urls: favArt, size: cardWidth, radius: 0, placeholderIcon: NaviGlyph.star, seed: coverSeed('Favorites')),
        paletteCoverId: starred.isEmpty ? null : starred.first.coverArt,
        width: cardWidth,
        onTap: () => navigateInApp(context, const FavoritesScreen()),
        onPlay: starred.isEmpty
            ? null
            : () => ref.read(playerProvider.notifier).playPlaylist(starred, shuffle: true, playlistName: 'Favorites'),
      ),
      _FeatureCard(
        title: 'Replay $year',
        subtitle: 'Your top songs, artists and listening time.',
        art: _ReplayArt(year: year, size: cardWidth),
        // Deep green, continuing the Replay art's accent.
        panel: Color.lerp(ThemeTokens.of(context).accent, ThemeTokens.of(context).bgBase, 0.76),
        width: cardWidth,
        onTap: () => navigateInApp(context, const ReplayScreen()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Top Picks for You'),
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

  /// First-run play: a server-side random mix, so it starts instantly even
  /// while the library mirror is still syncing.
  static Future<void> _shuffleLibrary(BuildContext context, WidgetRef ref) async {
    try {
      final songs = await ref.read(subsonicServiceProvider).getRandomSongs(size: 100);
      if (songs.isNotEmpty) {
        await ref.read(playerProvider.notifier).playPlaylist(songs, playlistName: 'Library Shuffle');
        return;
      }
    } catch (_) {}
    if (context.mounted) showToast(context, 'Couldn’t reach the library. Check your connection and try again.');
  }
}

/// Tall Top Picks card, as on Apple Music's Home: the artwork flowing into a
/// panel painted in the artwork's own colour, with the title and a line on
/// why it's here in white.
class _FeatureCard extends ConsumerWidget {
  /// Height added to the art: the text panel.
  static const double chrome = 92;

  final String title;
  final String subtitle;
  final Widget art;
  final double width;
  final VoidCallback onTap;

  /// Starts the music straight from Home, without opening the page.
  final VoidCallback? onPlay;

  /// Cover the panel colour is sampled from; [panel] overrides it.
  final String? paletteCoverId;
  final Color? panel;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.art,
    required this.width,
    required this.onTap,
    this.onPlay,
    this.paletteCoverId,
    this.panel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final sampled = paletteCoverId == null ? null : ref.watch(coverPaletteProvider(paletteCoverId!)).asData?.value;
    final ground = panel ?? sampled?.ground ?? t.bgSurface;
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.98,
      semanticLabel: '$title. $subtitle',
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.hero),
                child: AnimatedContainer(
                  duration: Motion.slow,
                  color: ground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        children: [
                          art,
                          // A short seam so the art melts into the panel.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: width * 0.28,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [ground.withValues(alpha: 0), ground],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.md + 2, Space.xs, Space.md, Space.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.title3.copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: Space.xxs),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.footnote.copyWith(color: Color.lerp(ground, Colors.white, 0.72)),
                                    ),
                                  ],
                                ),
                              ),
                              if (onPlay != null) ...[
                                const SizedBox(width: Space.sm),
                                _PlayDisc(onTap: onPlay!, label: 'Play $title'),
                              ],
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

/// White play disc on a Top Picks panel, inside a 44pt target.
class _PlayDisc extends StatelessWidget {
  static const double _disc = 34;
  final VoidCallback onTap;
  final String label;
  const _PlayDisc({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return CupertinoClickable(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      semanticLabel: label,
      child: const SizedBox.square(
        dimension: 44,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: _disc,
              child: Padding(
                // Optical centre: the triangle's mass sits left of its box.
                padding: EdgeInsets.only(left: 2),
                child: NaviIcon(NaviGlyph.play, size: 16, color: Colors.black),
              ),
            ),
          ),
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
        cardSize: _shelfCover,
        itemCount: albums.length.clamp(0, 15),
        itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
      );
    }
    final songs = ref.watch(recentlyPlayedSongsProvider).asData?.value ?? const <Song>[];
    final shown = songs.take(15).toList();
    return MediaShelf(
      title: 'Recently Played',
      cardSize: _shelfCover,
      itemCount: shown.length,
      itemBuilder: (context, i) => MediaCard(
        title: shown[i].title,
        subtitle: shown[i].artist,
        artUrl: _art(ref, shown[i].coverArt),
        size: _shelfCover,
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
      cardSize: _shelfCover,
      onSeeAll: () => navigateInApp(context, const PlaylistsPage()),
      itemCount: playlists.length.clamp(0, 15),
      itemBuilder: (context, i) {
        final p = playlists[i];
        return MediaCard(
          title: p.name,
          subtitle: songCount(p.songCount),
          artUrl: _art(ref, p.coverArt),
          size: _shelfCover,
          placeholderIcon: NaviGlyph.playlist,
          onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p)),
          onLongPress: () => showCollectionActions(
            context,
            title: p.name,
            subtitle: songCount(p.songCount),
            artUrl: _art(ref, p.coverArt),
            placeholderIcon: NaviGlyph.playlist,
            loadSongs: () => ref.read(subsonicServiceProvider).getPlaylistSongs(p.id),
            pin: Pin.playlist(p),
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
      cardSize: _shelfCover,
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
      size: _shelfCover,
      placeholderIcon: NaviGlyph.library,
      onTap: () => navigateInApp(context, AlbumDetailsScreen(album: album)),
      onLongPress: () => showCollectionActions(
        context,
        title: album.name,
        subtitle: album.artist,
        artUrl: art,
        placeholderIcon: NaviGlyph.library,
        loadSongs: () => ref.read(subsonicServiceProvider).getAlbum(album.id),
        pin: Pin.album(album),
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
        icon: NaviGlyph.home,
        art: EmptyArtKind.record,
        title: 'Your music will show up here',
        message: 'Play an album or make a playlist and Home fills in with what you listen to.',
      ),
    );
  }
}
