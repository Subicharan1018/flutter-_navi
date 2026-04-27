import 'dart:ui';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/options_menu.dart';
import '../core/theme.dart';
import 'song_picker_screen.dart';
import 'edit_playlist_screen.dart';

class PlaylistDetailsScreen extends ConsumerStatefulWidget {
  final Playlist playlist;
  const PlaylistDetailsScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends ConsumerState<PlaylistDetailsScreen> {
  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  bool _isLoading = true;
  Color _vibrantColor = AppTheme.surfaceLevel;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _searchController.addListener(_filterSongs);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    try {
      final service = ref.read(subsonicServiceProvider);
      final songs = await service.getPlaylistSongs(widget.playlist.id);

      final String? coverArtId = widget.playlist.coverArt ?? (songs.isNotEmpty ? songs.first.coverArt : null);

      if (coverArtId != null) {
        final imageUrl = service.getCoverArtUrl(coverArtId);
        final palette = await PaletteGenerator.fromImageProvider(
          CachedNetworkImageProvider(imageUrl),
          size: const Size(100, 100),
        );
        _vibrantColor =
            palette.vibrantColor?.color ?? palette.dominantColor?.color ?? AppTheme.surfaceLevel;
      }

      setState(() {
        _songs = songs;
        _filteredSongs = songs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterSongs() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSongs = _songs
          .where((song) =>
              song.title.toLowerCase().contains(query) ||
              song.artist.toLowerCase().contains(query))
          .toList();
    });
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    } else {
      return '$minutes min';
    }
  }

  int get _totalDurationSeconds => _songs.fold(0, (sum, song) => sum + song.duration);

  void _playAll({bool shuffle = false}) async {
    if (_songs.isEmpty) return;

    final playerNotifier = ref.read(playerProvider.notifier);
    // BUG FIX: Always start from index 0 regardless of shuffle.
    // When shuffling, the shuffle algorithm provides the randomness.
    // Previously, setting a random startIndex then immediately shuffling
    // caused a jump: random index → (shuffle rebuilds) → index 0
    await playerNotifier.setQueue(_songs, 0);
    if (shuffle) {
      debugPrint('👉 [UI] Playlist Shuffle Button Tapped');
      await playerNotifier.setShuffleMode(true);
    } else {
      await playerNotifier.setShuffleMode(false);
    }
  }

  Future<void> _deleteSong(int index) async {
    final song = _filteredSongs[index];
    final originalIndex = _songs.indexOf(song);

    setState(() {
      _songs.removeAt(originalIndex);
      _filterSongs();
    });

    try {
      final service = ref.read(subsonicServiceProvider);
      await service.updatePlaylist(widget.playlist.id, songIndexToRemove: originalIndex);
      ref.invalidate(playlistsProvider);
    } catch (e) {
      _loadSongs();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to remove song: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.coreBackground,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 480,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceLevel.withOpacity(0.5),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppTheme.textPrimary, size: 18),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  centerTitle: true,
                  title: _AppBarTitle(title: widget.playlist.name),
                  background: _FlexibleHeaderContent(
                    playlist: widget.playlist,
                    songs: _songs,
                    vibrantColor: _vibrantColor,
                    onPlayAll: () => _playAll(),
                    onShuffleAll: () => _playAll(shuffle: true),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
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
                        _loadSongs();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLevel.withOpacity(0.5),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: AppTheme.textPrimary, size: 22),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppTheme.surfaceLevel,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.edit_rounded,
                                      color: AppTheme.textPrimary),
                                  title: const Text('Edit Playlist',
                                      style: TextStyle(
                                          color: AppTheme.textPrimary, fontSize: 15)),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final changed = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditPlaylistScreen(playlist: widget.playlist),
                                      ),
                                    );
                                    if (changed == true) {
                                      _loadSongs();
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.redAccent),
                                  title: const Text('Delete Playlist',
                                      style: TextStyle(
                                          color: Colors.redAccent, fontSize: 15)),
                                  onTap: () async {
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLevel.withOpacity(0.5),
                        ),
                        child: const Icon(Icons.more_horiz_rounded,
                            color: AppTheme.textPrimary, size: 22),
                      ),
                    ),
                  ),
                ],
              ),

              // Song count + duration row AND search bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_songs.length} songs • ${_formatDuration(_totalDurationSeconds)}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 15),
                              cursorColor: AppTheme.electricBlue,
                              decoration: InputDecoration(
                                hintText: 'Search in playlist',
                                hintStyle: TextStyle(
                                    color: AppTheme.textMuted.withOpacity(0.6),
                                    fontSize: 15),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    color: AppTheme.textMuted, size: 18),
                                suffixIcon: value.text.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () => _searchController.clear(),
                                        child: const Icon(Icons.cancel_rounded,
                                            color: AppTheme.textMuted, size: 18),
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppTheme.surfaceLevel.withOpacity(0.55),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: AppTheme.outlineColor.withOpacity(0.25),
                                      width: 0.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: AppTheme.outlineColor.withOpacity(0.25),
                                      width: 0.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: AppTheme.electricBlue.withOpacity(0.5),
                                      width: 1),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Add Songs button — circular
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      GestureDetector(
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
                          _loadSongs();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.withOpacity(0.15),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: Colors.green, size: 24),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Add Songs',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Song list
              if (_isLoading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(color: AppTheme.electricBlue)))
              else
                SliverReorderableList(
                  itemCount: _filteredSongs.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    setState(() {
                      final item = _songs.removeAt(oldIndex);
                      _songs.insert(newIndex, item);
                      _filterSongs();
                    });
                  },
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(song.id),
                      index: index,
                      child: Dismissible(
                        key: ValueKey('dismiss_${song.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.redAccent,
                          child: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.textPrimary),
                        ),
                        onDismissed: (_) => _deleteSong(index),
                        child: SongTile(
                          song: song,
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .setQueue(_filteredSongs, index);
                          },
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) =>
                                  OptionsMenu(song: song, playlistId: widget.playlist.id),
                            );
                          },
                        )
                            .animate()
                            .fadeIn(
                                duration: 400.ms,
                                delay: (index * 40).clamp(0, 400).ms)
                            .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
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
            child: SafeArea(
              top: false,
              child: MiniPlayer(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  final String title;
  const _AppBarTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double opacity =
            (constraints.maxHeight - kToolbarHeight) / (480 - kToolbarHeight);
        return Opacity(
          opacity: (1 - opacity).clamp(0.0, 1.0),
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        );
      },
    );
  }
}

class _FlexibleHeaderContent extends StatelessWidget {
  final Playlist playlist;
  final List<Song> songs;
  final Color vibrantColor;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffleAll;

  const _FlexibleHeaderContent({
    required this.playlist,
    required this.songs,
    required this.vibrantColor,
    required this.onPlayAll,
    required this.onShuffleAll,
  });

  @override
  Widget build(BuildContext context) {
    final service = ProviderScope.containerOf(context).read(subsonicServiceProvider);
    final String? coverArtId = playlist.coverArt ?? (songs.isNotEmpty ? songs.first.coverArt : null);
    final String imageUrl = coverArtId != null ? service.getCoverArtUrl(coverArtId) : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final double topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
        final double currentHeight = constraints.maxHeight;
        final double t =
            ((currentHeight - topPadding) / (480 - topPadding)).clamp(0.0, 1.0);

        final double artworkScale = 0.7 + 0.3 * t;

        return Opacity(
          opacity: t,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred background
              if (imageUrl.isNotEmpty)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.5), BlendMode.darken),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.45, 0.8],
                      colors: [
                        vibrantColor.withOpacity(0.6),
                        vibrantColor.withOpacity(0.1),
                        AppTheme.coreBackground,
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Positioned(
                top: topPadding + (20 * t),
                left: 0,
                right: 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Artwork
                    Transform.scale(
                      scale: artworkScale,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.6),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(
                              color: AppTheme.outlineColor.withOpacity(0.3)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl, fit: BoxFit.cover)
                              : Container(
                                  color: AppTheme.surfaceLevel,
                                  child: const Icon(Icons.music_note_rounded,
                                      size: 80, color: AppTheme.textMuted)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Playlist name
                    Text(
                      playlist.name,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Apple Music',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Apple Music for Chances',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Play / Shuffle / Queue — all circular
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Shuffle button
                        GestureDetector(
                          onTap: onShuffleAll,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              border: Border.all(
                                color: AppTheme.textPrimary.withOpacity(0.8),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(Icons.shuffle_rounded,
                                color: AppTheme.textPrimary, size: 22),
                          ),
                        ),
                        const SizedBox(width: 24),

                        // Play button (larger, gradient filled)
                        GestureDetector(
                          onTap: onPlayAll,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF54EA2), Color(0xFFFF7676)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF54EA2).withOpacity(0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 36),
                          ),
                        ),
                        const SizedBox(width: 24),

                        // Queue button
                        GestureDetector(
                          onTap: () {}, // wire to queue action if needed
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              border: Border.all(
                                color: AppTheme.textPrimary.withOpacity(0.8),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(Icons.queue_music_rounded,
                                color: AppTheme.textPrimary, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}