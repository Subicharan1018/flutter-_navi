import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../core/theme.dart';

class EditPlaylistScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const EditPlaylistScreen({super.key, required this.playlist});

  @override
  ConsumerState<EditPlaylistScreen> createState() => _EditPlaylistScreenState();
}

class _EditPlaylistScreenState extends ConsumerState<EditPlaylistScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  bool _isSaving = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
    _descController = TextEditingController(text: widget.playlist.comment);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
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

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(subsonicServiceProvider);

      // Update basic info
      await service.updatePlaylist(
        widget.playlist.id,
        name: _nameController.text.trim(),
        comment: _descController.text.trim(),
      );

      // Upload image if selected
      if (_selectedImage != null) {
        await service.setPlaylistImage(widget.playlist.id, _selectedImage!);
      }

      ref.invalidate(playlistsProvider);
      // RC-18 FIX: Wait a frame for the provider to start re-fetching
      // before navigating back. This prevents the parent screen from
      // building with stale playlist data.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update playlist: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(subsonicServiceProvider);

    return Scaffold(
      backgroundColor: ThemeTokens.of(context).bgBase,
      appBar: AppBar(
        backgroundColor: ThemeTokens.of(context).bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: ThemeTokens.of(context).textPrimary,
              fontSize: 15,
            ),
          ),
        ),
        leadingWidth: 80,
        title: Text(
          'Edit Playlist',
          style: TextStyle(
            color: ThemeTokens.of(context).textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeTokens.of(context).accent,
                      ),
                    )
                  : Text(
                      'Done',
                      style: TextStyle(
                        color: ThemeTokens.of(context).accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 24),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: ThemeTokens.of(context).bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ThemeTokens.of(context).outline),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.cover)
                      : (widget.playlist.coverArt != null
                            ? CachedNetworkImage(
                                imageUrl: service.getCoverArtUrl(
                                  widget.playlist.coverArt!,
                                ),
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                Icons.music_note_rounded,
                                size: 64,
                                color: ThemeTokens.of(context).textMuted,
                              )),
                ),
              ),
            ),
            SizedBox(height: 12),
            TextButton(
              onPressed: _pickImage,
              child: Text(
                'Change Photo',
                style: TextStyle(
                  color: ThemeTokens.of(context).accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: 36),

            Container(
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeTokens.of(context).outline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _nameController,
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: 17,
                ),
                cursorColor: ThemeTokens.of(context).accent,
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(
                    color: ThemeTokens.of(context).textMuted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeTokens.of(context).outline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _descController,
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: 17,
                ),
                maxLines: 3,
                cursorColor: ThemeTokens.of(context).accent,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(
                    color: ThemeTokens.of(context).textMuted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
