import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import '../providers/settings_provider.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';

class NewReleasesScreen extends ConsumerStatefulWidget {
  const NewReleasesScreen({super.key});

  @override
  ConsumerState<NewReleasesScreen> createState() => _NewReleasesScreenState();
}

class _NewReleasesScreenState extends ConsumerState<NewReleasesScreen> {
  List<Album> _albums = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final service = ref.read(subsonicServiceProvider);
      _albums = await service.getAlbumList(type: 'newest', size: 50);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load albums: $e';
        });
      }
    }
  }

  void _onAlbumTap(Album album) async {
    // Fetch album songs and play
    try {
      final service = ref.read(subsonicServiceProvider);
      final songs = await service.getAlbum(album.id);
      if (songs.isNotEmpty && mounted) {
        ref.read(playerProvider.notifier).setQueue(songs, 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load album: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.coreBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.coreBackground,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'New Releases',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white60, size: 24),
                onPressed: _loadAlbums,
              ),
            ],
          ),

          // ── Loading / Error / Album grid ──
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                    color: AppTheme.electricBlue, strokeWidth: 2.5),
              ),
            )
          else if (_errorMessage.isNotEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.textMuted, size: 48),
                    const SizedBox(height: 12),
                    Text(_errorMessage,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loadAlbums,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _albums.length) return null;
                    final album = _albums[index];
                    return _NewReleaseCard(
                      album: album,
                      service: ref.read(subsonicServiceProvider),
                      onTap: () => _onAlbumTap(album),
                    );
                  },
                  childCount: _albums.length,
                ),
              ),
            ),

          // Bottom padding for mini player
          const SliverToBoxAdapter(
            child: SizedBox(height: 120),
          ),
        ],
      ),
    );
  }
}

class _NewReleaseCard extends StatelessWidget {
  final Album album;
  final dynamic service;
  final VoidCallback onTap;

  const _NewReleaseCard({
    required this.album,
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = service.getCoverArtUrl(album.coverArt);
    final cacheKey = 'cover_${album.coverArt}';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheKey: cacheKey,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => Container(
                  color: AppTheme.topLevel,
                  child: const Center(
                    child: Icon(Icons.album_rounded,
                        size: 48, color: AppTheme.textMuted),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppTheme.topLevel,
                  child: const Center(
                    child: Icon(Icons.album_rounded,
                        size: 48, color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
