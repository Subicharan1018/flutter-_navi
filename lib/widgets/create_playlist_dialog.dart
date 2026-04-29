import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';

class CreatePlaylistDialog extends ConsumerStatefulWidget {
  const CreatePlaylistDialog({super.key});

  @override
  ConsumerState<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<CreatePlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;
  File? _selectedImage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
      });
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      final service = ref.read(subsonicServiceProvider);
      await service.createPlaylist(name);

      // If image was selected, fetch the new playlist and set its image
      if (_selectedImage != null) {
        // Re-fetch playlists to get the newly created one
        final playlists = await service.getPlaylists();
        final newPl = playlists.where((p) => p.name == name).firstOrNull;
        if (newPl != null) {
          await service.setPlaylistImage(newPl.id, _selectedImage!);
        }
      }

      ref.invalidate(playlistsProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$name" created')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create playlist: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceLevel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.outlineColor),
      ),
      title: const Text(
        'New Playlist',
        style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.topLevel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.outlineColor),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedImage != null
                  ? Image.file(_selectedImage!, fit: BoxFit.cover)
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: AppTheme.spotifyGreen, size: 28),
                        SizedBox(height: 4),
                        Text('Add Photo',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 10)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
          // Name field
          TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            cursorColor: AppTheme.spotifyGreen,
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(
                  color: AppTheme.textMuted.withOpacity(0.5), fontSize: 15),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.spotifyGreen)),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppTheme.textMuted.withOpacity(0.3))),
            ),
            onSubmitted: (_) => _create(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        ),
        TextButton(
          onPressed: _isCreating ? null : _create,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.spotifyGreen))
              : const Text('Create',
                  style: TextStyle(
                      color: AppTheme.spotifyGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
        ),
      ],
    );
  }
}
