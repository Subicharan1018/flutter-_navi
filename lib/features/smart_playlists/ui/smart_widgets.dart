import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../logic/smart_playlist_providers.dart';

/// "Smart" marker on a playlist row.
class SmartBadge extends StatelessWidget {
  const SmartBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.capsule)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NaviIcon(NaviGlyph.smart, size: 11, color: t.textSecondary),
          const SizedBox(width: 3),
          Text('Smart', style: t.footnote.copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A smart playlist's artwork: the generated cover for its id.
class SmartCover extends StatelessWidget {
  final String id;
  final double size;
  final double radius;
  const SmartCover({super.key, required this.id, required this.size, this.radius = Radii.cover});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: GeneratedCover.seeded(seed: 'smart|$id', borderRadius: radius));
}

/// The square tile a glyph sits in on Playlists rows (New…, folders).
class GlyphTile extends StatelessWidget {
  final NaviGlyph glyph;
  final bool accent;
  const GlyphTile(this.glyph, {super.key, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.cover)),
      alignment: Alignment.center,
      child: NaviIcon(glyph, size: 26, color: accent ? t.accent : t.textPrimary),
    );
  }
}

/// Asks for a name (new folder, rename). Returns the trimmed text, or null
/// when cancelled or left blank.
Future<String?> showNamePrompt(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String placeholder = 'Name',
}) async {
  final t = ThemeTokens.of(context);
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: placeholder),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: t.body.copyWith(color: t.accent))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirmLabel, style: t.headline.copyWith(color: t.accent)),
        ),
      ],
    ),
  );
  controller.dispose();
  final clean = name?.trim() ?? '';
  return clean.isEmpty ? null : clean;
}

const _noFolder = '__none';
const _newFolder = '__new';

/// Moves [playlistId] (a server or smart playlist) into a folder, out of its
/// folder, or into a folder made on the spot.
Future<void> showFolderPicker(BuildContext context, ProviderContainer container, String playlistId) async {
  final state = container.read(playlistFoldersProvider);
  final names = {for (final f in state.folders) f.id: f.name};
  final choice = await showChoiceSheet<String>(
    context,
    title: 'Move to Folder',
    options: [_noFolder, for (final f in state.ordered) f.id, _newFolder],
    selected: state.folderOf(playlistId) ?? _noFolder,
    label: (id) => switch (id) {
      _noFolder => 'No Folder',
      _newFolder => 'New Folder…',
      _ => names[id] ?? 'Folder',
    },
  );
  if (choice == null || !context.mounted) return;
  final folders = container.read(playlistFoldersProvider.notifier);
  switch (choice) {
    case _noFolder:
      folders.move(playlistId, null);
    case _newFolder:
      final name = await showNamePrompt(context, title: 'New Folder', confirmLabel: 'Create', placeholder: 'Folder name');
      if (name != null) folders.move(playlistId, folders.create(name));
    default:
      folders.move(playlistId, choice);
      folders.setExpanded(choice, true);
  }
}

/// "Move to Folder…" row for a playlist's actions sheet.
class FolderMoveAction extends ConsumerWidget {
  final String playlistId;
  final BuildContext page;
  const FolderMoveAction({super.key, required this.playlistId, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final current = ref.watch(playlistFoldersProvider.select((s) {
      final id = s.folderOf(playlistId);
      return id == null ? null : s.folder(id)?.name;
    }));
    return SheetAction(
      label: 'Move to Folder…',
      detail: current,
      trailing: NaviIcon(NaviGlyph.folder, size: 21, color: t.textPrimary),
      onTap: () => showFolderPicker(page, ProviderScope.containerOf(page), playlistId),
    );
  }
}
