import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../screens/library_screen.dart' show SwipeToDismissSongTile;

class AddToPlaylistDialog extends ConsumerStatefulWidget {
  final Song song;

  const AddToPlaylistDialog({super.key, required this.song});

  @override
  ConsumerState<AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<AddToPlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  // Tracks which playlist IDs are currently mid-toggle so we can show a
  // per-row spinner and block double-taps independently per row.
  final Set<String> _togglingIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      final service = ref.read(subsonicServiceProvider);
      await service.createPlaylist(name);

      ref.invalidate(playlistsProvider);
      final playlists = await ref.read(playlistsProvider.future);

      final newPlaylist = playlists.firstWhere(
        (p) => p.name == name,
        orElse: () =>
            throw Exception('Playlist not found after creation'),
      );
      await service.updatePlaylist(newPlaylist.id,
          songIdToAdd: widget.song.id);

      // Invalidate after network call succeeds.
      ref.invalidate(songsInPlaylistProvider(newPlaylist.id));

      if (mounted) {
        _nameController.clear();
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.spotifyGreen,
            content: Text(
              'Created and added to $name',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create playlist: $e')));
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _toggleEntry(
    String playlistId,
    String playlistName,
    List<Song>? currentSongs,
  ) async {
    if (currentSongs == null) return;
    if (_togglingIds.contains(playlistId)) return;

    final service = ref.read(subsonicServiceProvider);
    final songId = widget.song.id;
    final isAdded = currentSongs.any((s) => s.id == songId);

    setState(() => _togglingIds.add(playlistId));

    try {
      if (isAdded) {
        // Fetch the authoritative server list before computing remove index.
        final freshSongs = await service.getPlaylistSongs(playlistId,
            forceRefresh: true);
        final serverIndex =
            freshSongs.indexWhere((s) => s.id == songId);

        if (serverIndex == -1) {
          ref.invalidate(songsInPlaylistProvider(playlistId));
          if (mounted) setState(() => _togglingIds.remove(playlistId));
          return;
        }

        await service.updatePlaylist(playlistId,
            songIndexToRemove: serverIndex);
      } else {
        await service.updatePlaylist(playlistId, songIdToAdd: songId);
      }

      // Invalidate AFTER the network call succeeds — prevents flicker.
      ref.invalidate(songsInPlaylistProvider(playlistId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 1),
            backgroundColor:
                isAdded ? AppTheme.topLevel : AppTheme.spotifyGreen,
            content: Text(
              isAdded
                  ? 'Removed from $playlistName'
                  : 'Added to $playlistName',
              style: TextStyle(
                color: isAdded ? AppTheme.textPrimary : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      ref.invalidate(songsInPlaylistProvider(playlistId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _togglingIds.remove(playlistId));
    }
  }

  // ---------------------------------------------------------------------------
  // Remove song from playlist — called by SwipeToDismissSongTile.
  // Includes a 4-second undo snackbar.
  // ---------------------------------------------------------------------------
  Future<void> _removeSongFromPlaylist(
    String playlistId,
    String playlistName,
  ) async {
    final service = ref.read(subsonicServiceProvider);
    final songId = widget.song.id;

    try {
      final freshSongs = await service.getPlaylistSongs(playlistId,
          forceRefresh: true);
      final serverIndex = freshSongs.indexWhere((s) => s.id == songId);
      if (serverIndex == -1) {
        ref.invalidate(songsInPlaylistProvider(playlistId));
        return;
      }

      await service.updatePlaylist(playlistId,
          songIndexToRemove: serverIndex);
      ref.invalidate(songsInPlaylistProvider(playlistId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: AppTheme.topLevel,
            content: Text('Removed from $playlistName',
                style:
                    const TextStyle(color: AppTheme.textPrimary)),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppTheme.spotifyGreen,
              onPressed: () async {
                await service.updatePlaylist(playlistId,
                    songIdToAdd: songId);
                ref.invalidate(songsInPlaylistProvider(playlistId));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Dialog(
      backgroundColor: AppTheme.surfaceLevel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.outlineColor, width: 1),
      ),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Add to Playlist', style: AppTheme.headingMd),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── New playlist creation ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.outlineColor),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: AppTheme.bodyMd,
                        cursorColor: AppTheme.spotifyGreen,
                        decoration: InputDecoration(
                          hintText: 'Create new playlist...',
                          hintStyle: AppTheme.technicalSm
                              .copyWith(color: AppTheme.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    _isCreating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.spotifyGreen),
                          )
                        : IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: AppTheme.spotifyGreen,
                                size: 28),
                            onPressed: _createAndAdd,
                          ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Text('Your Playlists', style: AppTheme.labelMd),
              const SizedBox(height: 8),

              // ── Playlist list ──────────────────────────────────────────
              Flexible(
                child: playlistsAsync.when(
                  data: (playlists) {
                    if (playlists.isEmpty) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.playlist_add,
                                  size: 48,
                                  color: AppTheme.textMuted),
                              const SizedBox(height: 12),
                              Text('No playlists yet',
                                  style: AppTheme.technicalSm),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const Divider(
                          color: AppTheme.outlineColor, height: 1),
                      itemBuilder: (context, index) {
                        final pl = playlists[index];

                        return Consumer(
                          builder: (context, ref, child) {
                            final songsAsync = ref.watch(
                                songsInPlaylistProvider(pl.id));
                            final isToggling =
                                _togglingIds.contains(pl.id);

                            return songsAsync.when(
                              data: (songs) {
                                final isAdded = songs.any(
                                    (s) => s.id == widget.song.id);

                                final tile = ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 4),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppTheme.topLevel,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                        Icons.music_note,
                                        color:
                                            AppTheme.textSecondary),
                                  ),
                                  title: Text(pl.name,
                                      style: AppTheme.bodyMd.copyWith(
                                          fontWeight:
                                              FontWeight.w600)),
                                  subtitle: Text(
                                      '${pl.songCount} songs',
                                      style: AppTheme.technicalXs),
                                  trailing: isToggling
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppTheme
                                                      .spotifyGreen),
                                        )
                                      : Icon(
                                          isAdded
                                              ? Icons.check_circle
                                              : Icons
                                                  .add_circle_outline,
                                          color: isAdded
                                              ? AppTheme.spotifyGreen
                                              : AppTheme.textMuted,
                                        ),
                                  onTap: isToggling
                                      ? null
                                      : () => _toggleEntry(
                                          pl.id, pl.name, songs),
                                );

                                // Wrap rows where the song is already added
                                // with swipe-to-remove (confirmation dialog
                                // prevents accidental deletions).
                                if (isAdded) {
                                  return SwipeToDismissSongTile(
                                    dismissKey:
                                        'dialog_${pl.id}_${widget.song.id}',
                                    onDelete: () =>
                                        _removeSongFromPlaylist(
                                            pl.id, pl.name),
                                    child: tile,
                                  );
                                }
                                return tile;
                              },
                              loading: () => ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 4),
                                title: Text(pl.name,
                                    style: AppTheme.bodyMd),
                                trailing: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.textMuted),
                                ),
                              ),
                              error: (_, __) => ListTile(
                                title: Text(pl.name,
                                    style: AppTheme.bodyMd),
                                trailing: const Icon(
                                    Icons.error_outline,
                                    color: Colors.red),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: AppTheme.spotifyGreen),
                    ),
                  ),
                  error: (e, st) => Center(
                    child: Text('Error loading playlists',
                        style: AppTheme.technicalSm),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Done',
                    style: AppTheme.bodyMd.copyWith(
                        color: AppTheme.spotifyGreen,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}