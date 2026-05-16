import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import 'song_picker_screen.dart';
import 'edit_playlist_screen.dart';
import 'playlist/widgets/playlist_widgets.dart';

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
      final coverArtId = widget.playlist.resolvedCoverArtId(songs);
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
      vibrant = await Future.microtask(() => _extractPlaylistPalette(imageUrl));
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

    // Feature 3: When offline, only play downloaded songs.
    final isOffline = ref.read(isOfflineProvider);
    List<Song> playable = _songs;
    if (isOffline) {
      final dlState = ref.read(downloadStateProvider);
      playable = _songs
          .where((s) =>
              dlState[s.id]?.status == SongDownloadStatus.downloaded)
          .toList();
      if (playable.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No downloaded songs available offline')),
          );
        }
        return;
      }
    }

    await ref.read(playerProvider.notifier).playPlaylist(playable, shuffle: shuffle, playlistName: widget.playlist.name);
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
        backgroundColor: ThemeTokens.of(context).bgSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: ThemeTokens.of(context).outline)),
        title: Text('Delete Playlist',
            style: TextStyle(
                color: ThemeTokens.of(context).textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${widget.playlist.name}"? This cannot be undone.',
          style: TextStyle(color: ThemeTokens.of(context).textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: ThemeTokens.of(context).textPrimary)),
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
            child: Text('Delete',
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
                  child: CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  // Title fades in only when collapsed
                  title: CollapsedTitle(title: widget.playlist.name),
                  titlePadding:
                      const EdgeInsets.only(left: 56, right: 56, bottom: 14),
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
                      // Invalidate cache so the next open fetches fresh data.
                      await ref
                          .read(subsonicServiceProvider)
                          .invalidatePlaylist(widget.playlist.id);
                      _loadSongs();
                    },
                  ),
                  SizedBox(width: 4),
                  CircleIconButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () => _showPlaylistMenu(),
                  ),
                  SizedBox(width: 8),
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
                      SizedBox(height: 12),
                      PlaylistSearchField(controller: _searchController),
                    ],
                  ),
                ),
              ),

              // ── Add Songs row ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: AddSongsRow(
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
                  child: SongListSkeleton(),
                )
              else if (_hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: tokens.textMuted, size: 48),
                        SizedBox(height: 12),
                        Text('Could not load songs',
                            style: TextStyle(color: tokens.textSecondary)),
                        SizedBox(height: 16),
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
                    final messenger = ScaffoldMessenger.of(context);
                    ref
                        .read(subsonicServiceProvider)
                        .setPlaylistSongs(widget.playlist.id, songIds)
                        .catchError((e) {
                      if (mounted) {
                        messenger.showSnackBar(
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
                      onLongPress: () => showPlatformSheet(
                        context: context,
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
    showPlatformSheet(
      context: context,
      title: 'Playlist Options',
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_rounded,
                  color: ThemeTokens.of(context).textPrimary),
              title: Text('Edit Playlist',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
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

