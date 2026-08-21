import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../models/download_state.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../providers/download_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/options_menu.dart';
import '../widgets/desktop_dialogs.dart';
import '../core/theme.dart';
import '../utils/platform_utils.dart';
import 'song_picker_screen.dart';
import 'playlist/widgets/playlist_widgets.dart';
import 'playlist/widgets/playlist_menu_sheet.dart';

// ---------------------------------------------------------------------------
// Isolate-safe color extraction
// ---------------------------------------------------------------------------
Future<Color?> _extractPlaylistPalette(String imageUrl) async {
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

// ---------------------------------------------------------------------------
// Playlist Details Screen — High-End Spotify Desktop & Mobile Experience
// ---------------------------------------------------------------------------
class PlaylistDetailsScreen extends ConsumerStatefulWidget {
  final Playlist playlist;
  const PlaylistDetailsScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailsScreen> createState() =>
      _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends ConsumerState<PlaylistDetailsScreen> {
  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  bool _isLoading = true;
  bool _hasError = false;
  Color? _vibrantColorOverride;
  String _coverImageUrl = '';
  String _coverCacheKey = '';
  int? _hoveredIndex;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSongs();
    });
    _searchController.addListener(_filterSongs);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadSongs() async {
    final service = ref.read(subsonicServiceProvider);

    try {
      final songs = await service.getPlaylistSongs(widget.playlist.id);

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _filteredSongs = List.of(songs);
        _isLoading = false;
        _hasError = false;
      });

      final coverArtId = widget.playlist.resolvedCoverArtId(songs);
      if (coverArtId != null && coverArtId.isNotEmpty) {
        _loadCoverAndPalette(service, coverArtId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = _songs.isEmpty;
      });
    }
  }

  Future<void> _loadCoverAndPalette(dynamic service, String coverArtId) async {
    final imageUrl = service.getCoverArtUrl(coverArtId) as String;
    final cacheKey = 'cover_$coverArtId';

    Color? vibrant = _vibrantColorOverride;
    if (imageUrl != _coverImageUrl) {
      vibrant = await Future.microtask(() => _extractPlaylistPalette(imageUrl));
    }

    if (!mounted) return;
    setState(() {
      _coverImageUrl = imageUrl;
      _coverCacheKey = cacheKey;
      _vibrantColorOverride = vibrant;
    });
  }

  void _filterSongs() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredSongs = query.isEmpty
          ? List.of(_songs)
          : _songs
                .where(
                  (s) =>
                      s.title.toLowerCase().contains(query) ||
                      s.artist.toLowerCase().contains(query) ||
                      s.album.toLowerCase().contains(query),
                )
                .toList();
    });
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

  int get _totalDurationSeconds => _songs.fold(0, (sum, s) => sum + s.duration);

  void _playAll({int initialIndex = 0, bool shuffle = false}) async {
    if (_songs.isEmpty) return;

    final isOffline = ref.read(isOfflineProvider);
    List<Song> playable = _filteredSongs;
    if (isOffline) {
      final dlState = ref.read(downloadStateProvider);
      playable = _filteredSongs
          .where((s) => dlState[s.id]?.status == SongDownloadStatus.downloaded)
          .toList();
      if (playable.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No downloaded songs available offline'),
            ),
          );
        }
        return;
      }
    }

    if (shuffle) {
      await ref
          .read(playerProvider.notifier)
          .playPlaylist(
            playable,
            shuffle: true,
            playlistName: widget.playlist.name,
          );
    } else {
      ref
          .read(playerProvider.notifier)
          .setQueue(playable, initialIndex.clamp(0, playable.length - 1));
    }
  }

  Future<void> _deleteSong(int filteredIndex) async {
    final song = _filteredSongs[filteredIndex];
    final originalIndex = _songs.indexOf(song);
    if (originalIndex == -1) return;

    setState(() {
      _songs.removeAt(originalIndex);
      _filterSongs();
    });

    try {
      final service = ref.read(subsonicServiceProvider);
      await service.updatePlaylist(
        widget.playlist.id,
        songIndexToRemove: originalIndex,
      );
      await service.invalidatePlaylist(widget.playlist.id);
      ref.invalidate(playlistsProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _songs.insert(originalIndex, song);
          _filterSongs();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove song: $e')));
      }
    }
  }

  void _confirmDeletePlaylist() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          'Delete from Your Library?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          'This will delete "${widget.playlist.name}" from Your Library.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(subsonicServiceProvider)
                    .deletePlaylist(widget.playlist.id);
                ref.invalidate(playlistsProvider);
                if (mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete playlist: $e')),
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final isDesktop = PlatformUtils.isDesktop || MediaQuery.of(context).size.width >= 800;
    final vibrantColor = _vibrantColorOverride ?? tokens.accent;

    if (isDesktop) {
      return _buildDesktopLayout(tokens, vibrantColor);
    }

    return _buildMobileLayout(tokens, vibrantColor);
  }

  // ===========================================================================
  // Authentic Spotify Desktop Playlist Layout
  // ===========================================================================
  Widget _buildDesktopLayout(AppThemeTokens tokens, Color vibrantColor) {
    final playerState = ref.watch(playerProvider);
    final isPlayingThisPlaylist = playerState.isPlaying &&
        playerState.queue.isNotEmpty &&
        _songs.any((s) => s.id == playerState.currentSong?.id);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ── 1. Dynamic Ambient Gradient Header ───────────────────────────
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
                    vibrantColor.withValues(alpha: 0.65),
                    vibrantColor.withValues(alpha: 0.25),
                    const Color(0xFF121212).withValues(alpha: 0.90),
                    const Color(0xFF121212),
                  ],
                  stops: const [0.0, 0.50, 0.85, 1.0],
                ),
              ),
            ),
          ),

          // ── 2. Scrollable Content ────────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Spotify Desktop Hero Header ─────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                  child: Row(
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
                                  cacheKey: _coverCacheKey,
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
                              'PLAYLIST',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.playlist.name,
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

                            if (widget.playlist.comment.isNotEmpty) ...[
                              Text(
                                widget.playlist.comment,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                            ],

                            // User info & stats row
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
                                const Text(
                                  'NaviVibe',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  ' \u2022 ${_songs.length} songs, ${_formatDuration(_totalDurationSeconds)}',
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
                  ),
                ),
              ),

              // ── Spotify Desktop Action Bar ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 4, 32, 16),
                  child: Row(
                    children: [
                      // Large Green Circular Play Button (52x52)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            if (isPlayingThisPlaylist) {
                              ref.read(playerProvider.notifier).player.pause();
                            } else {
                              _playAll();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
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
                                isPlayingThisPlaylist
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
                        onPressed: () => _playAll(shuffle: true),
                        tooltip: 'Shuffle Play',
                      ),
                      const SizedBox(width: 4),

                      // Add Songs Button
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SongPickerScreen(
                                playlistId: widget.playlist.id,
                                playlistName: widget.playlist.name,
                              ),
                            ),
                          );
                          await ref
                              .read(subsonicServiceProvider)
                              .invalidatePlaylist(widget.playlist.id);
                          _loadSongs();
                        },
                        tooltip: 'Add to this playlist',
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
                        tooltip: 'Download',
                      ),
                      const SizedBox(width: 4),

                      // More Options Menu
                      IconButton(
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                        onPressed: _showPlaylistMenu,
                        tooltip: 'More options',
                      ),

                      const Spacer(),

                      // Search in playlist field
                      Container(
                        width: 220,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search in playlist',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.white.withValues(alpha: 0.60),
                              size: 18,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      color: Colors.white70,
                                      size: 16,
                                    ),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Track Table Header Row ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 38,
                            child: Text(
                              '#',
                              style: TextStyle(
                                color: Color(0xFFB3B3B3),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Expanded(
                            flex: 5,
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
                                  size: 17,
                                  color: Color(0xFFB3B3B3),
                                ),
                                SizedBox(width: 12),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(
                        color: Color(0xFF282828),
                        height: 1,
                        thickness: 1,
                      ),
                      const SizedBox(height: 6),
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
                      'Could not load playlist tracks',
                      style: TextStyle(color: Color(0xFFB3B3B3)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _filteredSongs[index];
                        final isPlayingSong = playerState.currentSong?.id == song.id;
                        final isHovered = _hoveredIndex == index;
                        final service = ref.watch(subsonicServiceProvider);
                        final coverUrl = service.getCoverArtUrl(song.coverArt);

                        return MouseRegion(
                          onEnter: (_) => setState(() => _hoveredIndex = index),
                          onExit: (_) => setState(() => _hoveredIndex = null),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _playAll(initialIndex: index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  // Index / Play indicator
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

                                  // Small Artwork Thumbnail
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => Container(
                                        width: 40,
                                        height: 40,
                                        color: const Color(0xFF282828),
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: Color(0xFFB3B3B3),
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Track Title & Artist
                                  Expanded(
                                    flex: 5,
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
                                        const SizedBox(height: 3),
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

                                  // Album Column
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
                                          builder: (_) => OptionsMenu(
                                            song: song,
                                            playlistId: widget.playlist.id,
                                            onRemoveFromPlaylist: () => _deleteSong(index),
                                          ),
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
                      childCount: _filteredSongs.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Mobile Playlist Layout
  // ===========================================================================
  Widget _buildMobileLayout(AppThemeTokens tokens, Color vibrantColor) {
    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 380,
                pinned: true,
                stretch: true,
                backgroundColor: tokens.bgBase,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  title: CollapsedTitle(title: widget.playlist.name),
                  titlePadding: const EdgeInsets.only(
                    left: 56,
                    right: 56,
                    bottom: 14,
                  ),
                  background: _isLoading
                      ? LoadingHeader(playlist: widget.playlist)
                      : ExpandedHeader(
                          playlist: widget.playlist,
                          coverImageUrl: _coverImageUrl,
                          coverCacheKey: _coverCacheKey,
                          vibrantColor: vibrantColor,
                          songCount: _songs.length,
                          totalDuration: _formatDuration(_totalDurationSeconds),
                          songs: _songs,
                          onPlayAll: () => _playAll(),
                          onShuffleAll: () => _playAll(shuffle: true),
                          onDownloadAll: () => ref
                              .read(downloadStateProvider.notifier)
                              .downloadPlaylist(_songs),
                        ),
                ),
                actions: [
                  CircleIconButton(
                    icon: Icons.add_rounded,
                    size: 22,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SongPickerScreen(
                            playlistId: widget.playlist.id,
                            playlistName: widget.playlist.name,
                          ),
                        ),
                      );
                      await ref
                          .read(subsonicServiceProvider)
                          .invalidatePlaylist(widget.playlist.id);
                      _loadSongs();
                    },
                  ),
                  const SizedBox(width: 4),
                  CircleIconButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () => _showPlaylistMenu(),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // Search bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: PlaylistSearchField(controller: _searchController),
                ),
              ),

              // Song list
              if (_isLoading)
                const SliverFillRemaining(child: SongListSkeleton())
              else if (_hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Could not load songs',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: _filteredSongs.length,
                  onReorderItem: (oldIndex, newIndex) {
                    if (_searchController.text.isNotEmpty) return;
                    setState(() {
                      final item = _songs.removeAt(oldIndex);
                      _songs.insert(newIndex, item);
                      _filterSongs();
                    });
                    final songIds = _songs.map((s) => s.id).toList();
                    ref
                        .read(subsonicServiceProvider)
                        .setPlaylistSongs(widget.playlist.id, songIds);
                  },
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    Widget tileContent = SongTile(
                      song: song,
                      onTap: () => ref
                          .read(playerProvider.notifier)
                          .setQueue(_filteredSongs, index),
                      onLongPress: () => showPlatformSheet(
                        context: context,
                        builder: (_) => OptionsMenu(
                          song: song,
                          playlistId: widget.playlist.id,
                          onRemoveFromPlaylist: () => _deleteSong(index),
                        ),
                      ),
                    );

                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(song.id),
                      index: index,
                      child: Dismissible(
                        key: ValueKey('dismiss_${song.id}'),
                        direction: DismissDirection.endToStart,
                        background: const DismissBackground(),
                        onDismissed: (_) => _deleteSong(index),
                        child: RepaintBoundary(child: tileContent),
                      ),
                    );
                  },
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),

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

  Widget _placeholderCover() {
    return Container(
      color: const Color(0xFF282828),
      child: const Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: 64,
          color: Color(0xFFB3B3B3),
        ),
      ),
    );
  }

  void _showPlaylistMenu() {
    showPlatformSheet(
      context: context,
      title: 'Playlist Options',
      builder: (ctx) => PlaylistMenuSheet(
        playlist: widget.playlist,
        onPlaylistEdited: _loadSongs,
        onDeleteTapped: _confirmDeletePlaylist,
      ),
    );
  }
}
