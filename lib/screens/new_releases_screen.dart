import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../widgets/mini_player.dart';
import 'album_details_screen.dart';
import '../widgets/app_scaffold.dart';

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

  void _onAlbumTap(Album album) {
    navigateInApp(context, AlbumDetailsScreen(album: album));
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
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: ThemeTokens.of(context).textPrimary,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  'New Releases',
                  style: TextStyle(
                    color: ThemeTokens.of(context).textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: ThemeTokens.of(context).textSecondary,
                      size: 24,
                    ),
                    onPressed: _loadAlbums,
                  ),
                ],
              ),

              // ── Loading / Error / Album grid ──
              if (_isLoading)
                SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: ThemeTokens.of(context).accent,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else if (_errorMessage.isNotEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: ThemeTokens.of(context).textMuted,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          _errorMessage,
                          style: TextStyle(
                            color: ThemeTokens.of(context).textMuted,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 16),
                        TextButton(
                          onPressed: _loadAlbums,
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.75,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index >= _albums.length) return null;
                      final album = _albums[index];
                      return _NewReleaseCard(
                        album: album,
                        service: ref.read(subsonicServiceProvider),
                        onTap: () => _onAlbumTap(album),
                      );
                    }, childCount: _albums.length),
                  ),
                ),

              // Bottom padding for mini player
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
                memCacheWidth: 350,
                memCacheHeight: 350,
                placeholder: (context, url) => Container(
                  color: ThemeTokens.of(context).bgElevated,
                  child: Center(
                    child: Icon(
                      Icons.album_rounded,
                      size: 48,
                      color: ThemeTokens.of(context).textMuted,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: ThemeTokens.of(context).bgElevated,
                  child: Center(
                    child: Icon(
                      Icons.album_rounded,
                      size: 48,
                      color: ThemeTokens.of(context).textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: ThemeTokens.of(context).textPrimary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: ThemeTokens.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
