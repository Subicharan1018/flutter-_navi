import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';

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

  // UX FIX: Pending changes tracked locally, committed on Save.
  final Set<String> _pendingAdds = {};
  final Set<String> _pendingRemoves = {};
  bool _isSaving = false;

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
      await ref
          .read(playlistControllerProvider)
          .createAndAdd(name, widget.song.id);

      if (mounted) {
        _nameController.clear();
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created and added to $name'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create playlist: $e')),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  // UX FIX: Toggle is purely local — no network call. Committed in _save().
  void _toggleEntry(String playlistId, bool currentlyInPlaylist) {
    setState(() {
      if (currentlyInPlaylist) {
        if (_pendingRemoves.contains(playlistId)) {
          _pendingRemoves.remove(playlistId);
        } else {
          _pendingRemoves.add(playlistId);
          _pendingAdds.remove(playlistId);
        }
      } else {
        if (_pendingAdds.contains(playlistId)) {
          _pendingAdds.remove(playlistId);
        } else {
          _pendingAdds.add(playlistId);
          _pendingRemoves.remove(playlistId);
        }
      }
    });
  }

  bool _hasChanges() => _pendingAdds.isNotEmpty || _pendingRemoves.isNotEmpty;

  bool _isChecked(String playlistId, bool originallyIn) {
    if (_pendingAdds.contains(playlistId)) return true;
    if (_pendingRemoves.contains(playlistId)) return false;
    return originallyIn;
  }

  // UX FIX: Batch-save all pending changes.
  Future<void> _save() async {
    if (!_hasChanges()) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    final songId = widget.song.id;
    try {
      final successCount = await ref
          .read(playlistControllerProvider)
          .batchUpdate(
            songId: songId,
            adds: _pendingAdds,
            removes: _pendingRemoves,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated $successCount playlist${successCount == 1 ? '' : 's'}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Dialog(
      backgroundColor: ThemeTokens.of(context).bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: ThemeTokens.of(context).outline, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
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
                  Text(
                    'Add to Playlist',
                    style: ThemeTokens.of(context).headingMd,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: ThemeTokens.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // ── New playlist creation ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: ThemeTokens.of(context).bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeTokens.of(context).outline),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: ThemeTokens.of(context).bodyMd,
                        cursorColor: ThemeTokens.of(context).accent,
                        decoration: InputDecoration(
                          hintText: 'Create new playlist...',
                          hintStyle: ThemeTokens.of(context).technicalSm
                              .copyWith(
                                color: ThemeTokens.of(context).textMuted,
                              ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    _isCreating
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeTokens.of(context).accent,
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.add_circle,
                              color: ThemeTokens.of(context).accent,
                              size: 28,
                            ),
                            onPressed: _createAndAdd,
                          ),
                  ],
                ),
              ),

              SizedBox(height: 20),
              Text('Your Playlists', style: ThemeTokens.of(context).labelMd),
              SizedBox(height: 8),

              // ── Playlist list ──────────────────────────────────────────
              Flexible(
                child: playlistsAsync.when(
                  data: (playlists) {
                    if (playlists.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.playlist_add,
                                size: 48,
                                color: ThemeTokens.of(context).textMuted,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No playlists yet',
                                style: ThemeTokens.of(context).technicalSm,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => Divider(
                        color: ThemeTokens.of(context).outline,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final pl = playlists[index];

                        return Consumer(
                          builder: (context, ref, child) {
                            final songsAsync = ref.watch(
                              songsInPlaylistProvider(pl.id),
                            );

                            return songsAsync.when(
                              data: (songs) {
                                final originallyIn = songs.any(
                                  (s) => s.id == widget.song.id,
                                );
                                // UX FIX: Use local pending state for display.
                                final checked = _isChecked(pl.id, originallyIn);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: ThemeTokens.of(context).bgElevated,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.music_note,
                                      color: ThemeTokens.of(
                                        context,
                                      ).textSecondary,
                                    ),
                                  ),
                                  title: Text(
                                    pl.name,
                                    style: ThemeTokens.of(context).bodyMd
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${pl.songCount} songs',
                                    style: ThemeTokens.of(context).technicalXs,
                                  ),
                                  trailing: Icon(
                                    checked
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                    color: checked
                                        ? ThemeTokens.of(context).accent
                                        : ThemeTokens.of(context).textMuted,
                                  ),
                                  // UX FIX: Toggle local state only — no network call.
                                  onTap: () =>
                                      _toggleEntry(pl.id, originallyIn),
                                );
                              },
                              loading: () => ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                title: Text(
                                  pl.name,
                                  style: ThemeTokens.of(context).bodyMd,
                                ),
                                trailing: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ThemeTokens.of(context).textMuted,
                                  ),
                                ),
                              ),
                              error: (_, __) => ListTile(
                                title: Text(
                                  pl.name,
                                  style: ThemeTokens.of(context).bodyMd,
                                ),
                                trailing: Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  loading: () => Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: ThemeTokens.of(context).accent,
                      ),
                    ),
                  ),
                  error: (e, st) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 36,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load playlists',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: ThemeTokens.of(context).textPrimary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check your connection and try again.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: ThemeTokens.of(context).textSecondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () => ref.invalidate(playlistsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16),
              // UX FIX: Save button replaces the old Done button.
              // Commits all pending add/remove operations in one batch.
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: ThemeTokens.of(context).bodyMd.copyWith(
                          color: ThemeTokens.of(context).textMuted,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    _isSaving
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeTokens.of(context).accent,
                            ),
                          )
                        : TextButton(
                            onPressed: _save,
                            child: Text(
                              _hasChanges() ? 'Save' : 'Done',
                              style: ThemeTokens.of(context).bodyMd.copyWith(
                                color: ThemeTokens.of(context).accent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
