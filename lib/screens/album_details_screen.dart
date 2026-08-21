import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/album.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/download_provider.dart';
import '../widgets/options_menu.dart';
import '../widgets/desktop_dialogs.dart';
import '../core/theme.dart';
import '../utils/platform_utils.dart';

// ---------------------------------------------------------------------------
// Isolate-safe color extraction
// ---------------------------------------------------------------------------
Future<Color?> _extractAlbumPalette(String imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      ResizeImage(
        CachedNetworkImageProvider(imageUrl),
        width: 150,
        height: 150,
      ),
      size: const Size(100, 100),
    );
    return palette.vibrantColor?.color ??
        palette.dominantColor?.color ??
        palette.mutedColor?.color;
  } catch (_) {
    return null;
  }
}

// ===========================================================================
// Album Details Screen (Authentic Spotify Desktop & Mobile Experience)
// ===========================================================================

class AlbumDetailsScreen extends ConsumerStatefulWidget {
  final Album album;
  const AlbumDetailsScreen({super.key, required this.album});

  @override
  ConsumerState<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends ConsumerState<AlbumDetailsScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  bool _hasError = false;
  Color? _vibrantColor;
  String _coverImageUrl = '';
  final ScrollController _scrollController = ScrollController();
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAlbumData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbumData() async {
    final service = ref.read(subsonicServiceProvider);
    final coverUrl = service.getCoverArtUrl(widget.album.coverArt);
    _coverImageUrl = coverUrl;

    if (coverUrl.isNotEmpty) {
      _extractAlbumPalette(coverUrl).then((color) {
        if (mounted && color != null) {
          setState(() => _vibrantColor = color);
        }
      });
    }

    try {
      final songs = await service.getAlbum(widget.album.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = _songs.isEmpty;
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final d = Duration(seconds: totalSeconds);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h hr $m min';
    return '$m min';
  }

  String _formatTrackDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _totalDurationSeconds =>
      _songs.fold(0, (sum, s) => sum + s.duration);

  void _playAlbum({int initialIndex = 0, bool shuffle = false}) {
    if (_songs.isEmpty) return;
    if (shuffle) {
      ref.read(playerProvider.notifier).setQueue(_songs, 0);
      ref.read(playerProvider.notifier).toggleShuffle();
    } else {
      ref.read(playerProvider.notifier).setQueue(_songs, initialIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final themeColor = _vibrantColor ?? tokens.accent;
    final isDesktop = PlatformUtils.isDesktop || MediaQuery.of(context).size.width >= 800;
    final playerState = ref.watch(playerProvider);
    final isCurrentAlbumPlaying = playerState.isPlaying &&
        playerState.currentSong != null &&
        playerState.currentSong!.album == widget.album.name;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Dynamic Ambient Gradient Mesh Backdrop
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    themeColor.withValues(alpha: 0.65),
                    themeColor.withValues(alpha: 0.25),
                    const Color(0xFF121212).withValues(alpha: 0.90),
                    const Color(0xFF121212),
                  ],
                  stops: const [0.0, 0.50, 0.85, 1.0],
                ),
              ),
            ),
          ),

          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Spotify Desktop Hero Header ─────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: isDesktop
                      ? const EdgeInsets.fromLTRB(32, 24, 32, 16)
                      : EdgeInsets.fromLTRB(
                          16,
                          MediaQuery.of(context).padding.top + 16,
                          16,
                          16,
                        ),
                  child: isDesktop
                      ? _buildDesktopHero(tokens, themeColor)
                      : _buildMobileHero(tokens, themeColor),
                ),
              ),

              // ── Spotify Action Bar (Play, Shuffle, Download, Options) ────
              SliverToBoxAdapter(
                child: Padding(
                  padding: isDesktop
                      ? const EdgeInsets.fromLTRB(32, 4, 32, 16)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Large Green Circular Play Button (52x52)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            if (isCurrentAlbumPlaying) {
                              ref.read(playerProvider.notifier).player.pause();
                            } else {
                              _playAlbum();
                            }
                          },
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1DB954),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1DB954).withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                isCurrentAlbumPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Shuffle Toggle
                      IconButton(
                        icon: const Icon(
                          Icons.shuffle_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                        onPressed: () => _playAlbum(shuffle: true),
                        tooltip: 'Shuffle Play',
                      ),
                      const SizedBox(width: 4),

                      // Download Button
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_circle_down_outlined,
                          color: Colors.white70,
                          size: 24,
                        ),
                        onPressed: _songs.isNotEmpty
                            ? () => ref
                                .read(downloadStateProvider.notifier)
                                .downloadPlaylist(_songs)
                            : null,
                        tooltip: 'Download Album',
                      ),
                    ],
                  ),
                ),
              ),

              // ── Track Table Header (Desktop) ─────────────────────────────
              if (isDesktop)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 36,
                              child: Text(
                                '#',
                                style: TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              flex: 6,
                              child: Text(
                                'Title',
                                style: TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Expanded(
                              flex: 4,
                              child: Text(
                                'Album',
                                style: TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: const [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 16,
                                    color: Color(0xFFB3B3B3),
                                  ),
                                  SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(
                          color: Color(0xFF282828),
                          height: 1,
                          thickness: 1,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),

              // ── Song List / Track Table ──────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF1DB954)),
                  ),
                )
              else if (_hasError)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Could not load album tracks',
                      style: TextStyle(color: Color(0xFFB3B3B3)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 24 : 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _songs[index];
                        final isPlayingSong = playerState.currentSong?.id == song.id;
                        final isHovered = _hoveredIndex == index;

                        return MouseRegion(
                          onEnter: (_) => setState(() => _hoveredIndex = index),
                          onExit: (_) => setState(() => _hoveredIndex = null),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _playAlbum(initialIndex: index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  // Index / Play Icon
                                  SizedBox(
                                    width: 36,
                                    child: isHovered
                                        ? Icon(
                                            isPlayingSong && playerState.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: isPlayingSong
                                                ? const Color(0xFF1DB954)
                                                : Colors.white,
                                            size: 20,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: isPlayingSong
                                                  ? const Color(0xFF1DB954)
                                                  : const Color(0xFFB3B3B3),
                                              fontSize: 14,
                                              fontWeight: isPlayingSong
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Track Title & Artist
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          style: TextStyle(
                                            color: isPlayingSong
                                                ? const Color(0xFF1DB954)
                                                : Colors.white,
                                            fontSize: 14,
                                            fontWeight: isPlayingSong
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          song.artist,
                                          style: const TextStyle(
                                            color: Color(0xFFB3B3B3),
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Album Column (Desktop)
                                  if (isDesktop)
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        song.album,
                                        style: const TextStyle(
                                          color: Color(0xFFB3B3B3),
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                  // Right Options & Duration
                                  if (isHovered) ...[
                                    IconButton(
                                      icon: Icon(
                                        song.starred
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: song.starred
                                            ? const Color(0xFF1DB954)
                                            : Colors.white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        ref
                                            .read(playerProvider.notifier)
                                            .toggleStar(song.id);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.more_horiz_rounded,
                                        color: Colors.white70,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        showPlatformSheet(
                                          context: context,
                                          builder: (_) => OptionsMenu(song: song),
                                        );
                                      },
                                    ),
                                  ],

                                  // Duration
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      _formatTrackDuration(song.duration),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Color(0xFFB3B3B3),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _songs.length,
                    ),
                  ),
                ),

              // Bottom Spacer
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Desktop Hero Banner (Spotify horizontal layout) ──────────────────────
  Widget _buildDesktopHero(AppThemeTokens tokens, Color themeColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Square Cover Art (192x192 with drop shadow)
        Container(
          width: 192,
          height: 192,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.60),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _coverImageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _coverImageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _placeholderCover(),
                  )
                : _placeholderCover(),
          ),
        ),
        const SizedBox(width: 24),

        // Text & Metadata Stack
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'ALBUM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.album.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Metadata Row (Artist, Year, Songs count, Total duration)
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white.withValues(alpha: 0.20),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.album.artist,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' \u2022 ${_songs.isNotEmpty ? "${_songs.first.year} \u2022 " : ""}${_songs.length} songs, ${_formatDuration(_totalDurationSeconds)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Mobile Hero Banner ──────────────────────────────────────────────────
  Widget _buildMobileHero(AppThemeTokens tokens, Color themeColor) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _coverImageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _coverImageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _placeholderCover(),
                    )
                  : _placeholderCover(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.album.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.album.artist} \u2022 ${_songs.length} songs',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _placeholderCover() {
    return Container(
      color: const Color(0xFF282828),
      child: const Center(
        child: Icon(
          Icons.album_rounded,
          size: 64,
          color: Color(0xFFB3B3B3),
        ),
      ),
    );
  }
}
