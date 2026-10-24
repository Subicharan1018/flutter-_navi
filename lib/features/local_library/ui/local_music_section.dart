import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../logic/local_library_providers.dart';
import '../logic/local_models.dart';

/// Settings > Local music: the folders NaviVibe reads songs from, a rescan
/// button with progress, and how many songs were found.
class LocalMusicSection extends ConsumerWidget {
  const LocalMusicSection({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    LocalFolder? folder;
    try {
      folder = await pickLocalFolder();
    } catch (_) {
      if (context.mounted) showToast(context, 'Couldn’t open the folder picker. Try again.');
      return;
    }
    if (folder == null) return;
    final added = await ref.read(localFoldersProvider.notifier).add(folder);
    if (context.mounted && !added) showToast(context, 'That folder is already added.');
  }

  Future<void> _folderActions(BuildContext context, WidgetRef ref, LocalFolder folder) {
    return showPlatformSheet<void>(
      context: context,
      title: folder.name,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetGroup(children: [
          SheetAction(
            label: 'Scan This Folder',
            icon: NaviGlyph.repeat,
            onTap: () => ref.read(localScanProvider.notifier).scan(only: [folder]),
          ),
          SheetAction(
            label: 'Remove Folder',
            detail: 'Your files stay where they are.',
            icon: NaviGlyph.trash,
            destructive: true,
            onTap: () => ref.read(localFoldersProvider.notifier).remove(folder.id),
          ),
        ]),
      ),
    );
  }

  String _footer(int total, int dupes, bool hasFolders) {
    if (!hasFolders) {
      return 'Add a folder of songs on this device. They appear in Library under On this device, and play without a connection.';
    }
    final extra = dupes == 0 ? '' : ' $dupes already on your server ${dupes == 1 ? 'is' : 'are'} listed once.';
    return 'Scanned again each time the app opens; only new and changed files are read.$extra';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(localFoldersProvider);
    final scan = ref.watch(localScanProvider);
    final counts = ref.watch(localCountsProvider).asData?.value ?? (0, 0);
    final (total, dupes) = counts;

    final status = scan.running
        ? (scan.total == 0 ? 'Looking for songs…' : 'Reading ${scan.done} of ${scan.total}…')
        : scan.failed.isNotEmpty
            ? 'A folder couldn’t be read. Add it again to grant access.'
            : null;

    return GroupedSection(
      header: 'Local Music',
      footer: status ?? _footer(total, dupes, folders.isNotEmpty),
      children: [
        for (final f in folders)
          GroupedRow(
            title: f.name,
            subtitle: displayFolderPath(f.uri),
            icon: NaviGlyph.folder,
            onTap: () => _folderActions(context, ref, f),
          ),
        GroupedRow(
          title: 'Add Folder',
          icon: NaviGlyph.plus,
          showChevron: false,
          onTap: () => _add(context, ref),
        ),
        if (folders.isNotEmpty)
          GroupedRow(
            title: 'Scan Now',
            icon: NaviGlyph.repeat,
            value: total == 0 ? null : '$total ${total == 1 ? 'song' : 'songs'}',
            trailing: scan.running ? const CupertinoActivityIndicator() : null,
            showChevron: false,
            onTap: scan.running ? null : () => ref.read(localScanProvider.notifier).scan(),
          ),
      ],
    );
  }
}
