import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/playlist.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/cover_art.dart';
import '../widgets/ui/action_sheet.dart';
import 'playlist_details_screen.dart';

/// Opens the playlist editor as a full-screen sheet. With no [playlist] it
/// creates one (and opens it afterwards); otherwise it edits [playlist].
/// Returns true when something was saved.
Future<bool> showPlaylistEditor(BuildContext context, {Playlist? playlist}) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlaylistEditor(playlist: playlist)),
  );
  return saved == true;
}

/// Apple Music's New / Edit Playlist: a large artwork button, the title set
/// big and centred, a description, Cancel and Create/Done in the bar.
class PlaylistEditor extends ConsumerStatefulWidget {
  final Playlist? playlist;
  const PlaylistEditor({super.key, this.playlist});

  @override
  ConsumerState<PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends ConsumerState<PlaylistEditor> {
  late final _title = TextEditingController(text: widget.playlist?.name ?? '');
  late final _description = TextEditingController(text: widget.playlist?.comment ?? '');
  File? _image;
  bool _saving = false;

  bool get _creating => widget.playlist == null;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path != null) setState(() => _image = File(path));
  }

  Future<void> _save() async {
    final name = _title.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final svc = ref.read(subsonicServiceProvider);
    try {
      final playlist = _creating ? await ref.read(playlistControllerProvider).create(name) : widget.playlist!;
      await svc.updatePlaylist(
        playlist.id,
        name: _creating ? null : name,
        comment: _description.text.trim(),
      );
      if (_image != null) await svc.setPlaylistImage(playlist.id, _image!);
      await svc.invalidatePlaylist(playlist.id);
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final page = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(true);
      if (_creating && page.mounted) {
        showToast(page, 'Created “$name”');
        navigateInApp(page, PlaylistDetailsScreen(playlist: playlist));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, _creating ? 'Couldn’t create the playlist. Try again.' : 'Couldn’t save changes. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final existingArt = (widget.playlist?.coverArt ?? '').isEmpty
        ? null
        : ref.read(subsonicServiceProvider).getCoverArtUrl(widget.playlist!.coverArt);
    final canSave = _title.text.trim().isNotEmpty && !_saving;

    return Scaffold(
      backgroundColor: t.bgSurface,
      appBar: AppBar(
        backgroundColor: t.bgSurface,
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: Space.lg),
          onPressed: () => Navigator.of(context).pop(false),
          child: Align(alignment: Alignment.centerLeft, child: Text('Cancel', style: t.body.copyWith(color: t.accent))),
        ),
        title: Text(_creating ? 'New Playlist' : 'Edit Playlist', style: t.headline),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: Space.xl), child: CupertinoActivityIndicator())
              : CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  onPressed: canSave ? _save : null,
                  child: Text(
                    _creating ? 'Create' : 'Done',
                    style: t.headline.copyWith(color: canSave ? t.accent : t.textMuted),
                  ),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.xxl, Space.xxl, Space.xxl, Space.huge),
        children: [
          Center(
            child: CupertinoClickable(
              onTap: _pickImage,
              scaleFactor: 0.97,
              semanticLabel: 'Choose artwork',
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: t.bgElevated,
                  borderRadius: BorderRadius.circular(Radii.hero),
                  boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 10))],
                ),
                clipBehavior: Clip.antiAlias,
                child: _image != null
                    ? Image.file(_image!, fit: BoxFit.cover)
                    : existingArt != null
                        ? CoverArt(url: existingArt, size: 220, radius: 0)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle),
                                child: Icon(CupertinoIcons.camera_fill, color: t.accent, size: 24),
                              ),
                            ],
                          ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Center(
            child: CupertinoButton(
              onPressed: _pickImage,
              child: Text(
                _image != null || existingArt != null ? 'Change Artwork' : 'Add Artwork',
                style: t.body.copyWith(color: t.accent),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          CupertinoTextField(
            controller: _title,
            autofocus: _creating,
            placeholder: 'Playlist Title',
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            style: t.title2,
            placeholderStyle: t.title2.copyWith(color: t.textMuted),
            cursorColor: t.accent,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.lg),
          CupertinoTextField(
            controller: _description,
            placeholder: 'Description',
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            style: t.body,
            placeholderStyle: t.body.copyWith(color: t.textMuted),
            cursorColor: t.accent,
            decoration: BoxDecoration(color: t.bgElevated, borderRadius: BorderRadius.circular(Radii.control)),
            padding: const EdgeInsets.all(Space.md),
          ),
        ],
      ),
    );
  }
}
