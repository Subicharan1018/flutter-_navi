import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/settings_provider.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/mini_player.dart';

class MadeForYouScreen extends ConsumerStatefulWidget {
  const MadeForYouScreen({super.key});

  @override
  ConsumerState<MadeForYouScreen> createState() => _MadeForYouScreenState();
}

class _MadeForYouScreenState extends ConsumerState<MadeForYouScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final service = ref.read(subsonicServiceProvider);
      final recService = ref.read(recommendationProvider);

      // Fetch a pool of random songs from the server
      final allSongs = await service.getRandomSongs(size: 200);

      // If recommendations are enabled, use the personalized feed
      if (recService.enabled && recService.profiles.isNotEmpty) {
        _songs = recService.getPersonalizedFeed(allSongs, limit: 50);
      } else {
        _songs = allSongs;
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load songs: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeTokens.of(context).bgBase,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
          // ── App Bar ──
          SliverAppBar(
            pinned: true,
            backgroundColor: ThemeTokens.of(context).bgBase,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Made For You',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    color: Colors.white60, size: 24),
                onPressed: _loadSongs,
              ),
            ],
          ),

          // ── Hero banner ──
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3DE87C), Color(0xFF0D7A3E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Personalised Mix',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            )),
                        SizedBox(height: 6),
                        Text(
                          'Songs picked based on your listening habits',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                      onPressed: _songs.isNotEmpty
                          ? () {
                              ref
                                  .read(playerProvider.notifier)
                                  .playPlaylist(_songs, shuffle: true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Playing Personalised Mix'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Loading / Error / Song list ──
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                    color: ThemeTokens.of(context).accent, strokeWidth: 2.5),
              ),
            )
          else if (_errorMessage.isNotEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: ThemeTokens.of(context).textMuted, size: 48),
                    SizedBox(height: 12),
                    Text(_errorMessage,
                        style: TextStyle(
                            color: ThemeTokens.of(context).textMuted, fontSize: 14)),
                    SizedBox(height: 16),
                    TextButton(
                      onPressed: _loadSongs,
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _songs.length) return null;
                  final song = _songs[index];
                  return SongTile(
                    song: song,
                    onTap: () {
                      ref
                          .read(playerProvider.notifier)
                          .setQueue(_songs, index);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Playing Personalised Mix'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                },
                childCount: _songs.length,
              ),
            ),

          // Bottom padding for mini player
          const SliverToBoxAdapter(
            child: SizedBox(height: 120),
          ),
        ],
      ),
          // ── Mini player ────────────────────────────────────────────────
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: MiniPlayer()),
          ),
        ],
      ),
    );
  }
}
