import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_card.dart';
import '../widgets/mini_player.dart';

// ── INK & SIGNAL Design System ────────────────────────────────────────────────
class _DS {
  static const bg  = Color(0xFF0E0C09);
  static const s1  = Color(0xFF171410);
  static const s2  = Color(0xFF1F1C17);
  static const s3  = Color(0xFF2A2620);
  static const amber = Color(0xFFE8A020);
  static const blue  = Color(0xFF3B82F6);
  static const cream = Color(0xFFF5F0E8);
  static const muted = Color(0xFF7A7268);

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
}

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _selectedTab = 0; // 0: Songs, 1: Albums

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _DS.bg,
      body: Stack(
        children: [
          // ── Background Accents ──
          Positioned(
            top: -90, left: -70,
            child: _LightLeak(color: _DS.amber, size: 340, opacity: 0.05),
          ),
          Positioned(
            top: 200, right: -100,
            child: _LightLeak(color: _DS.blue, size: 260, opacity: 0.03),
          ),

          // ── Main Content ──
          RefreshIndicator(
            color: _DS.amber,
            backgroundColor: _DS.s2,
            displacement: topPad + 56,
            onRefresh: () async {
              ref.invalidate(favoritesProvider);
            },
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, topPad + 20, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: _DS.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'COLLECTION',
                              style: _DS.mono(9, w: FontWeight.w500)
                                  .copyWith(letterSpacing: 2.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: _DS.display(42),
                            children: [
                              const TextSpan(text: 'Favor'),
                              TextSpan(
                                text: 'ites.',
                                style: _DS.display(42, italic: true)
                                    .copyWith(color: _DS.amber),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Tab Switcher
                        Row(
                          children: [
                            _TabButton(
                              title: 'Songs',
                              isSelected: _selectedTab == 0,
                              onTap: () => setState(() => _selectedTab = 0),
                            ),
                            const SizedBox(width: 10),
                            _TabButton(
                              title: 'Albums',
                              isSelected: _selectedTab == 1,
                              onTap: () => setState(() => _selectedTab = 1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.03, end: 0),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 10)),

                // ── List/Grid content ──
                favoritesAsync.when(
                  data: (data) {
                    if (_selectedTab == 0) {
                      return _buildSongsList(data.songs);
                    } else {
                      return _buildAlbumsList(data.albums);
                    }
                  },
                  loading: () => const SliverFillRemaining(
                    child: Center(child: _Loader()),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    child: Center(
                      child: Text('Could not load favorites',
                          style: _DS.mono(13, c: _DS.muted)),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 150)),
              ],
            ),
          ),

          // ── Mini Player ──
          const Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsList(List<Song> songs) {
    if (songs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_border_rounded, color: _DS.muted, size: 40),
              const SizedBox(height: 16),
              Text('No favorite songs yet', style: _DS.mono(13)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songs[index];
          return SongTile(
            song: song,
            onTap: () {
              ref.read(playerProvider.notifier).setQueue(songs, index);
            },
          ).animate(delay: (index * 20).clamp(0, 300).ms).fadeIn(duration: 400.ms).slideX(begin: 0.02, end: 0);
        },
        childCount: songs.length,
      ),
    );
  }

  Widget _buildAlbumsList(List<Album> albums) {
    if (albums.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.album_outlined, color: _DS.muted, size: 40),
              const SizedBox(height: 16),
              Text('No favorite albums yet', style: _DS.mono(13)),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 0.76,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = albums[index];
            return AlbumCard(
              album: album,
              onTap: () {
                // Navigate to album details
              },
            ).animate(delay: (index * 40).clamp(0, 400).ms).fadeIn(duration: 500.ms).scale(begin: const Offset(0.96, 0.96));
          },
          childCount: albums.length,
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _DS.amber : _DS.s1,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? _DS.amber : Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: _DS.amber.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Text(
          title,
          style: _DS.mono(11, 
            c: isSelected ? Colors.black : _DS.cream,
            w: isSelected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

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
          colors: [color.withOpacity(opacity), color.withOpacity(0)],
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20, height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: _DS.amber,
      ),
    );
  }
}
