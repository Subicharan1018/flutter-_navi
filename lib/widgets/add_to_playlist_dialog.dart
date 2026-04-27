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
  ConsumerState<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<AddToPlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

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
      final playlists = await service.getPlaylists();
      ref.invalidate(playlistsProvider);
      
      final newPlaylist = playlists.firstWhere((p) => p.name == name, orElse: () => throw Exception('Playlist not found after creation'));
      await service.updatePlaylist(newPlaylist.id, songIdToAdd: widget.song.id);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to $name')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create playlist: $e')));
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _addToExisting(String playlistId, String playlistName) async {
    try {
      final service = ref.read(subsonicServiceProvider);
      await service.updatePlaylist(playlistId, songIdToAdd: widget.song.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to $playlistName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add to playlist: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return AlertDialog(
      backgroundColor: AppTheme.surfaceLevel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.outlineColor)),
      title: const Text('Add to Playlist', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                    cursorColor: AppTheme.electricBlue,
                    decoration: InputDecoration(
                      labelText: 'New Playlist Name',
                      labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      isDense: true,
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.electricBlue)),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.textMuted.withOpacity(0.3))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isCreating
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.electricBlue))
                    : IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.electricBlue, size: 28),
                        onPressed: _createAndAdd,
                      ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: AppTheme.outlineColor, height: 1),
            const SizedBox(height: 8),
            Flexible(
              child: playlistsAsync.when(
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No existing playlists', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: const Icon(Icons.playlist_play_rounded, color: AppTheme.textMuted),
                        title: Text(pl.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
                        onTap: () => _addToExisting(pl.id, pl.name),
                      );
                    },
                  );
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.electricBlue))),
                error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13))),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        ),
      ],
    );
  }
}
