import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../providers/download_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../logic/download_location.dart';

/// Where offline downloads are stored, how much room is left there, and
/// moving what is already downloaded.
class DownloadLocationSection extends ConsumerStatefulWidget {
  const DownloadLocationSection({super.key});

  @override
  ConsumerState<DownloadLocationSection> createState() => _DownloadLocationSectionState();
}

class _DownloadLocationSectionState extends ConsumerState<DownloadLocationSection> {
  static const _store = DownloadLocationStore();

  String? _custom = _store.read();
  int? _free;
  String? _moving;

  @override
  void initState() {
    super.initState();
    _refreshFree();
  }

  Future<void> _refreshFree() async {
    final dir = ref.read(offlineServiceProvider).downloadsDirectory ??
        (await getApplicationDocumentsDirectory()).path;
    final free = await freeSpaceBytes(dir);
    if (mounted) setState(() => _free = free);
  }

  String get _where => _custom == null ? 'App storage' : _custom!.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  /// Places an Android app can write without a permission: its own folder on
  /// each storage volume (the SD card, if there is one).
  Future<List<String>> _androidVolumes() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final dirs = await getExternalStorageDirectories() ?? const <Directory>[];
      return [for (final d in dirs) d.path];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _pick(_Pick pick) async {
    final parent = switch (pick) {
      _AppStorage() => null,
      _Folder(:final path) => path,
      _Browse() => await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a download folder'),
    };
    if (pick is _Browse && parent == null) return;
    if (parent == _custom) return;
    await _apply(parent);
  }

  Future<void> _apply(String? parent) async {
    final offline = ref.read(offlineServiceProvider);
    final count = offline.getDownloadedCount();
    var move = false;
    if (count > 0) {
      final answer = await showChoiceSheet<bool>(
        context,
        title: 'Move your $count downloaded ${count == 1 ? 'song' : 'songs'}?',
        options: const [true, false],
        selected: true,
        label: (v) => v ? 'Move Them' : 'Leave Them',
        detail: (v) => v ? 'Free up the old place. This can take a while.' : 'They stay in the old folder and won’t play from here.',
      );
      if (answer == null) return;
      move = answer;
    }
    setState(() => _moving = move ? 'Moving…' : 'Checking…');
    final error = await offline.setDownloadLocation(
      parent,
      moveExisting: move,
      onProgress: (done, total) {
        if (mounted) setState(() => _moving = 'Moving $done of $total…');
      },
    );
    if (!mounted) return;
    setState(() {
      _moving = null;
      if (error == null || error.contains('stay in the old folder')) _custom = parent;
    });
    showToast(context, error ?? 'Downloads now go to ${parent == null ? 'app storage' : _where}');
    ref.invalidate(downloadedBytesProvider);
    _refreshFree();
  }

  Future<void> _showChoices() async {
    final volumes = await _androidVolumes();
    if (!mounted) return;
    final pick = await showPlatformSheet<_Pick>(
      context: context,
      title: 'Download Location',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetGroup(children: [
          SheetAction(
            label: 'App Storage',
            detail: 'Private to NaviVibe; removed with the app.',
            icon: _custom == null ? NaviGlyph.check : null,
            onTap: () => Navigator.of(ctx).pop(const _AppStorage()),
            keepOpen: true,
          ),
          for (final v in volumes)
            SheetAction(
              label: volumes.length > 1 && v != volumes.first ? 'SD Card (App Folder)' : 'Device (App Folder)',
              detail: v,
              icon: _custom == v ? NaviGlyph.check : null,
              onTap: () => Navigator.of(ctx).pop(_Folder(v)),
              keepOpen: true,
            ),
          SheetAction(
            label: 'Choose Folder…',
            icon: NaviGlyph.folder,
            onTap: () => Navigator.of(ctx).pop(const _Browse()),
            keepOpen: true,
          ),
        ]),
      ),
    );
    if (pick != null) await _pick(pick);
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.read(offlineServiceProvider);
    final free = _free == null ? null : offline.formatSize(_free!);
    final busy = _moving != null;
    return GroupedSection(
      header: 'Download Location',
      footer: _custom == null
          ? 'Downloads are kept in the app’s private storage.'
          : 'Songs are saved in “$downloadsFolderName” inside $_custom.',
      children: [
        GroupedRow(
          title: 'Save Downloads To',
          subtitle: _moving,
          icon: NaviGlyph.folder,
          value: _where,
          trailing: busy ? const CupertinoActivityIndicator() : null,
          onTap: busy ? null : _showChoices,
        ),
        GroupedRow(
          title: 'Free Space',
          icon: NaviGlyph.signal,
          value: free ?? '—',
          showChevron: false,
        ),
      ],
    );
  }
}

sealed class _Pick {
  const _Pick();
}

class _AppStorage extends _Pick {
  const _AppStorage();
}

class _Folder extends _Pick {
  final String path;
  const _Folder(this.path);
}

class _Browse extends _Pick {
  const _Browse();
}
