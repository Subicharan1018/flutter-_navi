import 'dart:ui';
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

// ---------------------------------------------------------------------------
// Isolate-safe color extraction (unchanged)
// ---------------------------------------------------------------------------
Future<Color?> _extractPlaylistPalette(String imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl),
      size: const Size(100, 100),
    );
    return palette.vibrantColor?.color ?? palette.dominantColor?.color;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Playlist Details Screen
// ---------------------------------------------------------------------------
class PlaylistDetailsScreen extends ConsumerStatefulWidget {
  final Playlist playlist;
  const PlaylistDetailsScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailsScreen> createState() =>
      _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState
    extends ConsumerState<PlaylistDetailsScreen> {
  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  bool _isLoading = true;
  bool _hasError = false;
  Color? _vibrantColorOverride;
  String _coverImageUrl = '';
  String _coverCacheKey = '';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Track whether the initial animation has already run so re-entry doesn't
  // re-animate the list (avoids the "always re-animating on scroll" trap).
  bool _listAnimated = false;

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

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadSongs() async {
    final service = ref.read(subsonicServiceProvider);

    try {
      // getPlaylistSongs() checks SQLite first (~5 ms on a cache hit).
      // On a cache hit it returns immediately then fires a background refresh.
      // On a cache miss it waits for the network, parses off-thread, caches.
      final songs = await service.getPlaylistSongs(widget.playlist.id);

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _filteredSongs = List.of(songs);
        _isLoading = false;
        _hasError = false;
        _listAnimated = false;
      });

      // Determine cover art then load palette without blocking the list.
      final coverArtId =
          widget.playlist.coverArt ?? (songs.isNotEmpty ? songs.first.coverArt : null);
      if (coverArtId != null && coverArtId.isNotEmpty) {
        _loadCoverAndPalette(service, coverArtId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // Only show the hard error state when we have no songs to show.
        _hasError = _songs.isEmpty;
      });
    }
  }

  /// Loads the cover image URL and extracts the vibrant palette colour.
  /// Runs independently of [_loadSongs] so it never blocks the song list.
  Future<void> _loadCoverAndPalette(
    dynamic service,
    String coverArtId,
  ) async {
    final imageUrl = service.getCoverArtUrl(coverArtId) as String;
    final cacheKey = 'cover_$coverArtId';

    // Only re-extract palette when the cover art actually changes.
    Color? vibrant = _vibrantColorOverride;
    // CRIT-2: Do NOT use compute() here. PaletteGenerator.fromImageProvider
    // calls Flutter's image codec which requires the main-isolate Flutter engine.
    // compute() spawns a bare Dart isolate (no Flutter engine) → hangs or crashes.
    // Direct call is safe: the image is already cached by CachedNetworkImage.
    if (imageUrl != _coverImageUrl) {
      vibrant = await _extractPlaylistPalette(imageUrl);
    }

    if (!mounted) return;
    setState(() {
      _coverImageUrl = imageUrl;
      _coverCacheKey = cacheKey;
      _vibrantColorOverride = vibrant;
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _filterSongs() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredSongs = query.isEmpty
          ? List.of(_songs)
          : _songs
              .where((s) =>
                  s.title.toLowerCase().contains(query) ||
                  s.artist.toLowerCase().contains(query))
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

  int get _totalDurationSeconds =>
      _songs.fold(0, (sum, s) => sum + s.duration);

  void _playAll({bool shuffle = false}) async {
    if (_songs.isEmpty) return;
    await ref.read(playerProvider.notifier).playPlaylist(_songs, shuffle: shuffle);
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
          widget.playlist.id, songIndexToRemove: originalIndex);
      // Invalidate the SQLite cache so the next open fetches fresh data.
      await service.invalidatePlaylist(widget.playlist.id);
      ref.invalidate(playlistsProvider);
    } catch (e) {
      // Restore the optimistically-removed song without a full reload.
      // Calling _loadSongs() here would set _isLoading=true and flash the
      // skeleton loader, which is jarring and unnecessary.
      if (mounted) {
        setState(() {
          _songs.insert(originalIndex, song);
          _filterSongs();
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove song: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete entire playlist (BUG-5)
  // ---------------------------------------------------------------------------

  void _confirmDeletePlaylist() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceLevel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.outlineColor)),
        title: const Text('Delete Playlist',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${widget.playlist.name}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textPrimary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              try {
                await ref
                    .read(subsonicServiceProvider)
                    .deletePlaylist(widget.playlist.id);
                ref.invalidate(playlistsProvider);
                if (mounted) Navigator.pop(context); // return to previous screen
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to delete playlist: $e')),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final vibrantColor = _vibrantColorOverride ?? tokens.bgSurface;

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Flexible App Bar ────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 460,
                pinned: true,
                stretch: true,
                backgroundColor: tokens.bgBase,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  // Title fades in only when collapsed
                  title: _CollapsedTitle(title: widget.playlist.name),
                  titlePadding:
                      const EdgeInsets.only(left: 56, right: 56, bottom: 14),
                  background: _isLoading
                      ? _LoadingHeader(playlist: widget.playlist)
                      : _ExpandedHeader(
                          playlist: widget.playlist,
                          coverImageUrl: _coverImageUrl,
                          coverCacheKey: _coverCacheKey,
                          vibrantColor: vibrantColor,
                          songCount: _songs.length,
                          totalDuration: _formatDuration(_totalDurationSeconds),
                          onPlayAll: () => _playAll(),
                          onShuffleAll: () => _playAll(shuffle: true),
                        ),
                ),
                actions: [
                  _CircleIconButton(
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
                      // Invalidate cache so the next open fetches fresh data.
                      await ref
                          .read(subsonicServiceProvider)
                          .invalidatePlaylist(widget.playlist.id);
                      _loadSongs();
                    },
                  ),
                  const SizedBox(width: 4),
                  _CircleIconButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () => _showPlaylistMenu(),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── Search bar + meta ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isLoading)
                        Text(
                          '${_songs.length} songs • ${_formatDuration(_totalDurationSeconds)}',
                          style: TextStyle(
                              color: tokens.textMuted, fontSize: 13),
                        ).animate().fadeIn(duration: 300.ms),
                      const SizedBox(height: 12),
                      _SearchField(controller: _searchController),
                    ],
                  ),
                ),
              ),

              // ── Add Songs row ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _AddSongsRow(
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
                      // Invalidate cache so the next open fetches fresh data.
                      await ref
                          .read(subsonicServiceProvider)
                          .invalidatePlaylist(widget.playlist.id);
                      _loadSongs();
                    },
                  ),
                ),
              ),

              // ── Song list ────────────────────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(
                  child: _SongListSkeleton(),
                )
              else if (_hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: tokens.textMuted, size: 48),
                        const SizedBox(height: 12),
                        Text('Could not load songs',
                            style: TextStyle(color: tokens.textSecondary)),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _loadSongs();
                          },
                          child: Text('Retry',
                              style:
                                  TextStyle(color: tokens.accent)),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_filteredSongs.isEmpty &&
                  _searchController.text.isNotEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('No songs match your search',
                        style: TextStyle(color: tokens.textMuted)),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: _filteredSongs.length,
                  onReorder: (oldIndex, newIndex) {
                    // CRIT-4: Reorder is disabled when search is active because
                    // _filteredSongs indices don't map 1:1 to _songs, so
                    // oldIndex/newIndex would remove the wrong server entry.
                    if (_searchController.text.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Clear search to reorder songs')),
                      );
                      return;
                    }
                    if (newIndex > oldIndex) newIndex -= 1;
                    setState(() {
                      final item = _songs.removeAt(oldIndex);
                      _songs.insert(newIndex, item);
                      _filterSongs();
                    });
                    // Sync new order to server (fire-and-forget).
                    final songIds = _songs.map((s) => s.id).toList();
                    ref
                        .read(subsonicServiceProvider)
                        .setPlaylistSongs(widget.playlist.id, songIds)
                        .catchError((e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Failed to save order: $e')),
                        );
                      }
                    });
                  },
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];

                    // -------------------------------------------------------
                    // KEY RULE: SliverReorderableList requires the widget
                    // returned by itemBuilder to have a non-null key at the
                    // very top level.  We must NEVER wrap the
                    // ReorderableDelayedDragStartListener in .animate() or any
                    // other wrapper — that strips the key from the root.
                    //
                    // Instead, the animation lives on the SongTile *inside*
                    // the Dismissible so the keyed listener is always root.
                    // -------------------------------------------------------

                    // Build the inner song tile, optionally animated.
                    Widget tileContent = SongTile(
                      song: song,
                      onTap: () => ref
                          .read(playerProvider.notifier)
                          .setQueue(_filteredSongs, index),
                      onLongPress: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => OptionsMenu(
                          song: song,
                          playlistId: widget.playlist.id,
                          onRemoveFromPlaylist: () => _deleteSong(index),
                        ),
                      ),
                    );

                    // Only animate on first load; skip on scroll rebuilds.
                    if (!_listAnimated) {
                      tileContent = tileContent
                          .animate()
                          .fadeIn(
                            duration: 350.ms,
                            delay: (index * 30).clamp(0, 280).ms,
                          )
                          .slideY(
                            begin: 0.04,
                            end: 0,
                            duration: 350.ms,
                            delay: (index * 30).clamp(0, 280).ms,
                            curve: Curves.easeOut,
                          );

                      // After the last item's animation frame, mark done.
                      if (index == _filteredSongs.length - 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _listAnimated = true);
                        });
                      }
                    }

                    // Keyed listener is ALWAYS the root widget returned.
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(song.id),
                      index: index,
                      child: Dismissible(
                        key: ValueKey('dismiss_${song.id}'),
                        direction: DismissDirection.endToStart,
                        background: _DismissBackground(),
                        onDismissed: (_) => _deleteSong(index),
                        child: tileContent,
                      ),
                    );
                  },
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 140)),
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

  // ---------------------------------------------------------------------------
  // Playlist options bottom sheet
  // ---------------------------------------------------------------------------
  void _showPlaylistMenu() {
    final tokens = ThemeTokens.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: tokens.outline,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: tokens.textPrimary),
              title: Text('Edit Playlist',
                  style: TextStyle(color: tokens.textPrimary, fontSize: 15)),
              onTap: () async {
                Navigator.pop(ctx);
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditPlaylistScreen(playlist: widget.playlist),
                  ),
                );
                if (changed == true) _loadSongs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Delete Playlist',
                  style: TextStyle(color: Colors.redAccent, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeletePlaylist();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Sub-widgets — all const-constructable / stateless for zero rebuild overhead
// ===========================================================================

// ---------------------------------------------------------------------------
// Collapsed app-bar title (fades in when scrolled up)
// ---------------------------------------------------------------------------
class _CollapsedTitle extends StatelessWidget {
  final String title;
  const _CollapsedTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    // FlexibleSpaceBar handles the opacity transition internally when pinned.
    // We just supply the styled text; no manual LayoutBuilder math needed.
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: tokens.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton placeholder shown while songs are loading
// ---------------------------------------------------------------------------
class _SongListSkeleton extends StatelessWidget {
  const _SongListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 10,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, i) => _SkeletonTile()
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1200.ms,
            delay: (i * 60).ms,
            color: Colors.white.withOpacity(0.06),
          ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 13,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 11,
                  width: 120,
                  decoration: BoxDecoration(
                    color: tokens.bgSurface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state header (shown while _isLoading)
// ---------------------------------------------------------------------------
class _LoadingHeader extends StatelessWidget {
  final Playlist playlist;
  const _LoadingHeader({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      decoration: BoxDecoration(color: tokens.bgBase),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing placeholder art
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(16),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 600.ms)
                .then()
                .fadeOut(duration: 600.ms),
            const SizedBox(height: 24),
            Container(
              width: 160,
              height: 20,
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(8),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 600.ms, delay: 100.ms)
                .then()
                .fadeOut(duration: 600.ms),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fully expanded header (shown after songs are loaded)
// ---------------------------------------------------------------------------
class _ExpandedHeader extends StatelessWidget {
  final Playlist playlist;
  final String coverImageUrl;
  final String coverCacheKey;
  final Color vibrantColor;
  final int songCount;
  final String totalDuration;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffleAll;

  const _ExpandedHeader({
    required this.playlist,
    required this.coverImageUrl,
    required this.coverCacheKey,
    required this.vibrantColor,
    required this.songCount,
    required this.totalDuration,
    required this.onPlayAll,
    required this.onShuffleAll,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final tokens = ThemeTokens.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Blurred background
        if (coverImageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              // PERF-4: reduced from σ48 to σ28 — decorative bg blur, imperceptible above σ20.
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.55), BlendMode.darken),
                child: CachedNetworkImage(
                  imageUrl: coverImageUrl,
                  cacheKey: '${coverCacheKey}_bg', // separate key for blurred bg
                  fit: BoxFit.cover,
                  // No placeholder — blurred bg is decorative, silence errors
                  errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),

        // ── Gradient scrim (top tint → transparent → bgBase)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 0.78, 1.0],
                colors: [
                  vibrantColor.withOpacity(0.55),
                  vibrantColor.withOpacity(0.08),
                  tokens.bgBase.withOpacity(0.8),
                  tokens.bgBase,
                ],
              ),
            ),
          ),
        ),

        // ── Content
        Positioned(
          top: topPadding + 12,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Artwork
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.65),
                      blurRadius: 36,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                    if (vibrantColor != tokens.bgSurface)
                      BoxShadow(
                        color: vibrantColor.withOpacity(0.28),
                        blurRadius: 48,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: coverImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverImageUrl,
                          cacheKey: coverCacheKey, // ← stable key
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                              color: tokens.bgSurface,
                              child: Icon(Icons.music_note_rounded,
                                  size: 72, color: tokens.textMuted)),
                          errorWidget: (_, __, ___) => Container(
                              color: tokens.bgSurface,
                              child: Icon(Icons.music_note_rounded,
                                  size: 72, color: tokens.textMuted)),
                        )
                      : Container(
                          color: tokens.bgSurface,
                          child: Icon(Icons.music_note_rounded,
                              size: 72, color: tokens.textMuted)),
                ),
              ),
              const SizedBox(height: 20),

              // Playlist name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: tokens.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Subtitle — song count + duration (real data, no hardcoded strings)
              Text(
                '$songCount songs • $totalDuration',
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),

              // Play / Shuffle buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  _HeaderButton(
                    size: 52,
                    onTap: onShuffleAll,
                    filled: false,
                    child: Icon(Icons.shuffle_rounded,
                        color: tokens.textPrimary, size: 22),
                  ),
                  const SizedBox(width: 20),

                  // Play (larger, accent filled)
                  _HeaderButton(
                    size: 64,
                    onTap: onPlayAll,
                    filled: true,
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 36),
                  ),
                  const SizedBox(width: 20),

                  // Queue
                  _HeaderButton(
                    size: 52,
                    onTap: () {},
                    filled: false,
                    child: Icon(Icons.queue_music_rounded,
                        color: tokens.textPrimary, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable header button (filled = accent gradient, unfilled = ghost)
// ---------------------------------------------------------------------------
class _HeaderButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final bool filled;
  final Widget child;

  const _HeaderButton({
    required this.size,
    required this.onTap,
    required this.filled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFFF54EA2), Color(0xFFFF7676)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: filled ? null : Colors.white.withOpacity(0.10),
          border: filled
              ? null
              : Border.all(
                  color: tokens.textPrimary.withOpacity(0.55),
                  width: 1.5,
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: const Color(0xFFF54EA2).withOpacity(0.40),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dismiss background (swipe-to-delete)
// ---------------------------------------------------------------------------
class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.redAccent.withOpacity(0.85),
          ],
        ),
      ),
      child: const Icon(Icons.delete_outline_rounded,
          color: Colors.white, size: 24),
    );
  }
}

// ---------------------------------------------------------------------------
// Search field — extracted so ValueListenableBuilder only rebuilds this widget
// ---------------------------------------------------------------------------
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: controller,
            style: TextStyle(color: tokens.textPrimary, fontSize: 15),
            cursorColor: tokens.accent,
            decoration: InputDecoration(
              hintText: 'Search in playlist',
              hintStyle: TextStyle(
                  color: tokens.textMuted.withOpacity(0.6), fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded,
                  color: tokens.textMuted, size: 18),
              suffixIcon: value.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => controller.clear(),
                      child: Icon(Icons.cancel_rounded,
                          color: tokens.textMuted, size: 18),
                    )
                  : null,
              filled: true,
              fillColor: tokens.bgSurface.withOpacity(0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.outline.withOpacity(0.25), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.outline.withOpacity(0.25), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: tokens.accent.withOpacity(0.55), width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add songs row
// ---------------------------------------------------------------------------
class _AddSongsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSongsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.12),
              border: Border.all(
                  color: Colors.green.withOpacity(0.45), width: 1.5),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 14),
          Text(
            'Add Songs',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable circular icon button (app bar back / add / more)
// ---------------------------------------------------------------------------
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.bgSurface.withOpacity(0.55),
        ),
        child: Icon(icon, color: tokens.textPrimary, size: size),
      ),
    );
  }
}
