import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/album_card.dart';
import '../core/navigation_transitions.dart';
import 'settings_screen.dart';
import 'playlist_details_screen.dart';
import 'made_for_you_screen.dart';
import 'new_releases_screen.dart';
import 'favorites_screen.dart';

// ── INK & SIGNAL Design System ────────────────────────────────────────────────
class _DS {
  // Backgrounds: warm charcoal, not cold blue-black
  static const bg  = Color(0xFF0E0C09);
  static const s1  = Color(0xFF171410);
  static const s2  = Color(0xFF1F1C17);
  static const s3  = Color(0xFF2A2620);

  // Single dominant accent + one cold contrast
  static const amber     = Color(0xFFE8A020);
  static const amberDim  = Color(0xFF6B4A0E);
  static const blue      = Color(0xFF3B82F6);
  static const cream     = Color(0xFFF5F0E8);
  static const muted     = Color(0xFF7A7268);

  // Palette per index (warm-first ordering)
  static const List<Color> palette = [
    Color(0xFFE8A020), // amber
    Color(0xFF3B82F6), // blue
    Color(0xFFF43F5E), // rose
    Color(0xFF10B981), // emerald
    Color(0xFFA855F7), // violet
    Color(0xFF22D3EE), // cyan
  ];
  static Color a(int i) => palette[i % palette.length];

  // ── Typography ──────────────────────────────────────────────────────────────
  // Display: Playfair Display — editorial, serif authority
  // Body/meta: DM Mono — calm, precise, monospaced provenance feel
  // Sub-body: Literata — warm readable serif for names

  static TextStyle display(double sz, {bool italic = false}) => TextStyle(
    fontFamily: 'PlayfairDisplay',
    fontSize: sz,
    fontWeight: FontWeight.w900,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: cream,
    letterSpacing: sz > 28 ? -1.5 : -0.6,
    height: 0.95,
  );

  static TextStyle mono(double sz, {Color? c, FontWeight w = FontWeight.w400}) =>
      TextStyle(
        fontFamily: 'DMMonoPro',
        fontSize: sz,
        fontWeight: w,
        color: c ?? muted,
        letterSpacing: sz < 11 ? 2.0 : 0.3,
        height: 1.3,
      );

  static TextStyle serif(double sz, {Color? c, FontWeight w = FontWeight.w600}) =>
      TextStyle(
        fontFamily: 'Literata',
        fontSize: sz,
        fontWeight: w,
        color: c ?? cream,
        letterSpacing: -0.2,
        height: 1.3,
      );

  // pubspec.yaml additions needed:
  //   - google_fonts: ^6.x  OR add these to assets/fonts/
  //   PlayfairDisplay-Black.ttf, DMMonoPro-Regular.ttf, Literata-SemiBold.ttf
}

// If using google_fonts package instead of bundled fonts, replace _DS font
// families with: GoogleFonts.playfairDisplay(...), GoogleFonts.dmMono(...)
// etc. and remove fontFamily strings.

// ── Home Screen ───────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _sc = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sc.addListener(() => _scrollOffset.value = _sc.offset);
  }

  @override
  void dispose() {
    _sc.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  String _greet() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync    = ref.watch(recentlyPlayedAlbumsProvider);
    final frequentAsync  = ref.watch(frequentAlbumsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final topPad         = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _DS.bg,
        body: Stack(
          children: [
            // ── Warm amber light leak (top-left only, intentional) ───────────
            Positioned(
              top: -90, left: -70,
              child: _LightLeak(color: _DS.amber, size: 340, opacity: 0.07),
            ),
            // Cold blue counter-light (right edge, subtler)
            Positioned(
              top: 200, right: -100,
              child: _LightLeak(color: _DS.blue, size: 260, opacity: 0.035),
            ),

            // ── Scroll content ───────────────────────────────────────────────
            RefreshIndicator(
              color: _DS.amber,
              backgroundColor: _DS.s2,
              displacement: topPad + 56,
              onRefresh: () async {
                ref.invalidate(recentlyPlayedAlbumsProvider);
                ref.invalidate(frequentAlbumsProvider);
                ref.invalidate(playlistsProvider);
              },
              child: CustomScrollView(
                controller: _sc,
                physics: const BouncingScrollPhysics(),
                slivers: [

                  // ── Header ─────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _Header(
                      greeting: _greet(),
                      topPad: topPad,
                      onSettings: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 6)),

                  // ── Quick Play (asymmetric hero grid) ───────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Quick Play')
                    .animate(delay: 60.ms).fadeIn(duration: 400.ms),
                  ),
                  SliverToBoxAdapter(
                    child: playlistsAsync.when(
                      data: (playlists) {
                        if (playlists.isEmpty) return const SizedBox();
                        return _QuickPlayGrid(
                          items: playlists.take(6).toList(),
                          onTap: (pl) async {
                            final svc = ref.read(subsonicServiceProvider);
                            try {
                              final songs = await svc.getPlaylistSongs(pl.id);
                              if (context.mounted) {
                                ref.read(playerProvider.notifier).setQueue(songs, 0);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not play "${pl.name}": $e')),
                                );
                              }
                            }
                          },
                        ).animate(delay: 80.ms).fadeIn(duration: 400.ms);
                      },
                      loading: () => const SizedBox(height: 110, child: Center(child: _Loader())),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),

                  // ── Explore (Discover) ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Explore')
                    .animate(delay: 120.ms).fadeIn(duration: 400.ms),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DiscoverCard(
                              tag: 'Curated',
                              title: 'Made\nFor You',
                              accentChar: '✦',
                              accentColor: _DS.amber,
                              bgColor: const Color(0xFF1A1308),
                              borderColor: const Color(0xFF2A2010),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const MadeForYouScreen())),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DiscoverCard(
                              tag: 'Saved',
                              title: 'Your\nFavorites',
                              accentChar: '♥',
                              accentColor: const Color(0xFFF43F5E),
                              bgColor: const Color(0xFF1A080A),
                              borderColor: const Color(0xFF2A1012),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const FavoritesScreen())),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DiscoverCard(
                              tag: 'Fresh',
                              title: 'New\nReleases',
                              accentChar: '↯',
                              accentColor: _DS.blue,
                              bgColor: const Color(0xFF08101A),
                              borderColor: const Color(0xFF101828),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const NewReleasesScreen())),
                            ),
                          ),
                        ],
                      ),
                    ).animate(delay: 130.ms).fadeIn(duration: 400.ms),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 4)),

                  // ── Monthly Replay ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Monthly Replay', onSeeAll: () {})
                    .animate(delay: 160.ms).fadeIn(duration: 400.ms),
                  ),
                  SliverToBoxAdapter(
                    child: frequentAsync.when(
                      data: (albums) => _AlbumReel(
                        albums: albums,
                        onTap: (a) async {
                          final svc = ref.read(subsonicServiceProvider);
                          try {
                            final songs = await svc.getAlbum(a.id);
                            if (context.mounted) {
                              ref.read(playerProvider.notifier).setQueue(songs, 0);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not play "${a.name}": $e')),
                              );
                            }
                          }
                        },
                      ).animate(delay: 180.ms).fadeIn(duration: 400.ms),
                      loading: () => const _ShimmerReel(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),

                  // ── Recent Playlists ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Recent Playlists', onSeeAll: () {})
                    .animate(delay: 220.ms).fadeIn(duration: 400.ms),
                  ),
                  SliverToBoxAdapter(
                    child: playlistsAsync.when(
                      data: (playlists) {
                        if (playlists.isEmpty) return const SizedBox();
                        return SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: playlists.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: _PlaylistCard(
                                playlist: playlists[i],
                                index: i,
                                onTap: () => Navigator.push(
                                  context,
                                  AppRouteTransitions.fadeScale(
                                    builder: (_) => PlaylistDetailsScreen(playlist: playlists[i]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      loading: () => const _ShimmerReel(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ),

                  // ── Your Playlists (numbered list) ──────────────────────────
                  SliverToBoxAdapter(
                    child: _SectionHeader(title: 'Your Playlists')
                    .animate(delay: 260.ms).fadeIn(duration: 400.ms),
                  ),
                  playlistsAsync.when(
                    data: (playlists) => SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _PlaylistRow(
                          playlist: playlists[i],
                          index: i,
                          isLast: i == playlists.length - 1,
                          onTap: () async {
                            final svc = ref.read(subsonicServiceProvider);
                            try {
                              final songs = await svc.getPlaylistSongs(playlists[i].id);
                              if (context.mounted) {
                                ref.read(playerProvider.notifier).setQueue(songs, 0);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not play "${playlists[i].name}": $e')),
                                );
                              }
                            }
                          },
                        ),
                        childCount: playlists.length,
                      ),
                    ),
                    loading: () => const SliverToBoxAdapter(
                        child: SizedBox(height: 80, child: Center(child: _Loader()))),
                    error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 150)),
                ],
              ),
            ),

            // ── Sticky frosted bar ───────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) {
                  final opacity = (offset / 60).clamp(0.0, 1.0);
                  return AnimatedOpacity(
                    opacity: opacity,
                    duration: Duration.zero,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          height: topPad + 50,
                          decoration: BoxDecoration(
                            color: _DS.bg.withOpacity(0.88),
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.white.withOpacity(0.05), width: 0.5)),
                          ),
                          padding: EdgeInsets.fromLTRB(20, topPad + 10, 20, 0),
                          child: Row(
                            children: [
                              Text('Home', style: _DS.display(20)),
                              const Spacer(),
                              _IconBtn(icon: Icons.notifications_none_rounded, onTap: () {}),
                              const SizedBox(width: 8),
                              _IconBtn(
                                icon: Icons.settings_outlined,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String greeting;
  final double topPad;
  final VoidCallback onSettings;
  const _Header({required this.greeting, required this.topPad, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Pulsing amber dot — "you are live, tuned in"
                    _PulseDot(),
                    const SizedBox(width: 7),
                    Text(
                      greeting.toUpperCase(),
                      style: _DS.mono(9, w: FontWeight.w500)
                          .copyWith(letterSpacing: 2.5, color: _DS.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Italic accent on last letter — editorial flourish
                RichText(
                  text: TextSpan(
                    style: _DS.display(42),
                    children: [
                      const TextSpan(text: 'Ho'),
                      TextSpan(
                        text: 'me.',
                        style: _DS.display(42, italic: true)
                            .copyWith(color: _DS.amber),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 4),
              _IconBtn(icon: Icons.notifications_none_rounded, onTap: () {}),
              const SizedBox(height: 8),
              _IconBtn(icon: Icons.settings_outlined, onTap: onSettings),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick Play — Asymmetric Hero Grid ─────────────────────────────────────────
// Hero tile spans full width + is taller. Remaining tiles in 2-col rows.
class _QuickPlayGrid extends StatelessWidget {
  final List<Playlist> items;
  final void Function(Playlist) onTap;
  const _QuickPlayGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox();
    final rest = items.length > 1 ? items.sublist(1) : <Playlist>[];
    final rows = (rest.length / 2).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Hero tile — first playlist gets spotlight
          _QuickTile(
            playlist: items[0],
            index: 0,
            isHero: true,
            onTap: () => onTap(items[0]),
          ),
          const SizedBox(height: 8),
          for (int r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (int c = 0; c < 2; c++) Builder(builder: (_) {
                    final i = r * 2 + c + 1; // offset by hero
                    if (i >= items.length) return const Expanded(child: SizedBox());
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: c == 1 ? 8 : 0),
                        child: _QuickTile(
                          playlist: items[i],
                          index: i,
                          isHero: false,
                          onTap: () => onTap(items[i]),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickTile extends ConsumerWidget {
  final Playlist playlist;
  final int index;
  final bool isHero;
  final VoidCallback onTap;
  const _QuickTile({
    required this.playlist,
    required this.index,
    required this.isHero,
    required this.onTap,
  });

  Color get _ac => _DS.a(index);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final height = isHero ? 70.0 : 54.0;
    final artSize = height;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 120.ms,
        height: height,
        decoration: BoxDecoration(
          color: _DS.s1,
          borderRadius: BorderRadius.circular(isHero ? 14 : 10),
          border: Border.all(color: _ac.withOpacity(0.12), width: 0.7),
          boxShadow: [
            BoxShadow(color: _ac.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          children: [
            // Artwork / color block
            SizedBox(
              width: artSize, height: artSize,
              child: playlist.coverArt != null
                  ? CachedNetworkImage(
                      imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_ac.withOpacity(0.9), _ac.withOpacity(0.35)],
                        ),
                      ),
                      child: Icon(Icons.queue_music_rounded,
                          color: Colors.white.withOpacity(0.7),
                          size: isHero ? 26 : 20),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    playlist.name,
                    maxLines: isHero ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: _DS.serif(isHero ? 15 : 13),
                  ),
                  if (isHero) ...[
                    const SizedBox(height: 3),
                    Text('${playlist.songCount} songs',
                        style: _DS.mono(10)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Play button
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _ac.withOpacity(0.14),
              ),
              child: Icon(Icons.play_arrow_rounded, color: _ac, size: 17),
            ),
          ],
        ),
      ),
    )
    .animate(delay: (index * 45).clamp(0, 280).ms)
    .fadeIn(duration: 380.ms)
    .slideX(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

// ── Discover Card — editorial asymmetric ─────────────────────────────────────
class _DiscoverCard extends StatelessWidget {
  final String tag;
  final String title;
  final String accentChar;
  final Color accentColor;
  final Color bgColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _DiscoverCard({
    required this.tag,
    required this.title,
    required this.accentChar,
    required this.accentColor,
    required this.bgColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.7),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Giant character bleeds off top-right — not a blob, a glyph
            Positioned(
              top: -14, right: -8,
              child: Text(
                accentChar,
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                  color: accentColor.withOpacity(0.07),
                  height: 1,
                ),
              ),
            ),
            // Content anchored bottom-left
            Positioned(
              left: 0, bottom: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag.toUpperCase(),
                      style: _DS.mono(8, c: accentColor, w: FontWeight.w500)
                          .copyWith(letterSpacing: 2.0),
                    ),
                    const SizedBox(height: 5),
                    Text(title, style: _DS.display(20).copyWith(height: 1.1)),
                  ],
                ),
              ),
            ),
            // Arrow — bottom right
            Positioned(
              bottom: 14, right: 14,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.12),
                ),
                child: Icon(Icons.chevron_right_rounded, color: accentColor, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Album Reel — first card is featured (taller) ──────────────────────────────
class _AlbumReel extends StatelessWidget {
  final List<Album> albums;
  final void Function(Album) onTap;
  const _AlbumReel({required this.albums, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final isFeatured = i == 0;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _AlbumItem(
              album: albums[i],
              isFeatured: isFeatured,
              index: i,
              onTap: () => onTap(albums[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumItem extends ConsumerWidget {
  final Album album;
  final bool isFeatured;
  final int index;
  final VoidCallback onTap;
  const _AlbumItem({
    required this.album,
    required this.isFeatured,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    final artW = isFeatured ? 130.0 : 110.0;
    final artH = isFeatured ? 155.0 : 110.0;
    final ac = _DS.a(index);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: artW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: artW,
                  height: artH,
                  decoration: BoxDecoration(
                    color: _DS.s2,
                    borderRadius: BorderRadius.circular(isFeatured ? 12 : 8),
                    boxShadow: [
                      BoxShadow(
                        color: ac.withOpacity(0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: album.coverArt != null
                      ? CachedNetworkImage(
                          imageUrl: svc.getCoverArtUrl(album.coverArt!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                ac.withOpacity(0.6),
                                ac.withOpacity(0.15),
                                _DS.s3,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                          child: Icon(Icons.album_rounded,
                              color: Colors.white.withOpacity(0.3),
                              size: isFeatured ? 40 : 28),
                        ),
                ),
                // "Featured" rotated label on first item only
                if (isFeatured)
                  Positioned(
                    left: 0, top: 20,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: _DS.bg,
                        child: Text('FEATURED',
                            style: _DS.mono(7, c: _DS.amber, w: FontWeight.w500)
                                .copyWith(letterSpacing: 1.5)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _DS.serif(12)),
            const SizedBox(height: 3),
            Text(album.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _DS.mono(10)),
          ],
        ),
      ),
    )
    .animate(delay: (index * 40).clamp(0, 280).ms)
    .fadeIn(duration: 400.ms)
    .slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }
}

// ── Playlist Card (recent) ────────────────────────────────────────────────────
class _PlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final int index;
  final VoidCallback onTap;
  const _PlaylistCard({required this.playlist, required this.index, required this.onTap});

  Color get _ac => _DS.a(index);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 130, height: 130,
                  decoration: BoxDecoration(
                    color: _DS.s2,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _ac.withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: playlist.coverArt != null
                      ? CachedNetworkImage(
                          imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _ac.withOpacity(0.75),
                                _ac.withOpacity(0.25),
                                _DS.s3,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                          child: Center(
                            child: Icon(Icons.queue_music_rounded,
                                color: Colors.white.withOpacity(0.8), size: 34),
                          ),
                        ),
                ),
                // Bottom gradient fade
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [_DS.bg.withOpacity(0.6), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _DS.serif(12)),
            const SizedBox(height: 3),
            Text('${playlist.songCount} songs',
                style: _DS.mono(10)),
          ],
        ),
      ),
    )
    .animate(delay: (index * 40).clamp(0, 280).ms)
    .fadeIn(duration: 400.ms)
    .slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }
}

// ── Playlist Row — numbered, editorial ────────────────────────────────────────
class _PlaylistRow extends ConsumerWidget {
  final Playlist playlist;
  final int index;
  final bool isLast;
  final VoidCallback onTap;
  const _PlaylistRow({
    required this.playlist,
    required this.index,
    required this.isLast,
    required this.onTap,
  });

  Color get _ac => _DS.a(index);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(subsonicServiceProvider);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: Colors.white.withOpacity(0.05), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Italic number — editorial music-list feel
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.right,
                style: _DS.display(18, italic: true)
                    .copyWith(color: _DS.amberDim, height: 1.2),
              ),
            ),
            const SizedBox(width: 14),
            // Artwork
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: _ac.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: playlist.coverArt != null
                    ? CachedNetworkImage(
                        imageUrl: svc.getCoverArtUrl(playlist.coverArt!),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_ac.withOpacity(0.85), _ac.withOpacity(0.35)],
                          ),
                        ),
                        child: Icon(Icons.queue_music_rounded,
                            color: Colors.white.withOpacity(0.9), size: 18),
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _DS.serif(14)),
                  const SizedBox(height: 3),
                  Text('Playlist · ${playlist.songCount} songs',
                      style: _DS.mono(10)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Play button — subtle ring
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _DS.amber.withOpacity(0.22), width: 0.7),
              ),
              child: Icon(Icons.play_arrow_rounded, color: _DS.amber, size: 17),
            ),
          ],
        ),
      ),
    )
    .animate(delay: (index * 32).clamp(0, 280).ms)
    .fadeIn(duration: 360.ms)
    .slideY(begin: 0.03, end: 0, curve: Curves.easeOutCubic);
  }
}

// ── Section Header — with rule line ──────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: _DS.display(22).copyWith(height: 1.2)),
          const SizedBox(width: 12),
          // Rule line — structural not decorative
          Expanded(
            child: Container(
              height: 0.5,
              color: Colors.white.withOpacity(0.07),
            ),
          ),
          if (onSeeAll != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onSeeAll,
              child: Text('All',
                  style: _DS.mono(10, c: _DS.amber, w: FontWeight.w500)
                      .copyWith(letterSpacing: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Icon Button ───────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: _DS.s2,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 0.5),
        ),
        child: Icon(icon, color: _DS.muted, size: 17),
      ),
    );
  }
}

// ── Pulse Dot ─────────────────────────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}
class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 5, height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _DS.amber.withOpacity(_anim.value),
          boxShadow: [
            BoxShadow(
              color: _DS.amber.withOpacity(_anim.value * 0.7),
              blurRadius: 5, spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Light Leak (replaces blobs) ───────────────────────────────────────────────
class _LightLeak extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _LightLeak({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(opacity), Colors.transparent],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}

// ── Loader ────────────────────────────────────────────────────────────────────
class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18, height: 18,
    child: CircularProgressIndicator(color: _DS.amber, strokeWidth: 1.4),
  );
}

// ── Shimmer Reel ──────────────────────────────────────────────────────────────
class _ShimmerReel extends StatelessWidget {
  const _ShimmerReel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 5,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: i == 0 ? 130 : 110,
                height: i == 0 ? 155 : 110,
                decoration: BoxDecoration(
                  color: _DS.s2,
                  borderRadius: BorderRadius.circular(i == 0 ? 12 : 8),
                ),
              ),
              const SizedBox(height: 9),
              Container(width: 72, height: 8,
                  decoration: BoxDecoration(color: _DS.s3, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 5),
              Container(width: 48, height: 7,
                  decoration: BoxDecoration(color: _DS.s2, borderRadius: BorderRadius.circular(4))),
            ],
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 800.ms)
        .then()
        .fadeOut(duration: 800.ms),
      ),
    );
  }
}