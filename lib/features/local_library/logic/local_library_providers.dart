import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/hive_boxes.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import 'file_source.dart';
import 'local_library_service.dart';
import 'local_models.dart';
import 'scanner.dart';

class HiveFolderStore implements FolderStore {
  @override
  List<LocalFolder> read() {
    try {
      final raw = HiveBoxes.prefs.get(HiveBoxes.kLocalFolders);
      if (raw is! List) return const [];
      return [for (final r in raw) ?LocalFolder.fromJson(r)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<LocalFolder> folders) =>
      HiveBoxes.prefs.put(HiveBoxes.kLocalFolders, [for (final f in folders) f.toJson()]);
}

/// Covers pulled from tags live here, apart from the server's image cache.
Future<Directory> localArtDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}local_art');
}

Stream<ScanEvent> _isolateScan({required List<LocalFolder> folders, required Map<String, String> known}) async* {
  final art = await localArtDirectory();
  yield* scanInIsolate(folders: folders, known: known, artDir: art.path);
}

final localLibraryServiceProvider = Provider<LocalLibraryService>((ref) {
  return LocalLibraryService(ref.watch(appDatabaseProvider), HiveFolderStore(), runScan: _isolateScan);
});

/// The folders the user added, in the order added.
class LocalFoldersNotifier extends Notifier<List<LocalFolder>> {
  @override
  List<LocalFolder> build() => ref.read(localLibraryServiceProvider).folders;

  /// Adds a folder and scans it. False when it was already there.
  Future<bool> add(LocalFolder folder) async {
    final added = await ref.read(localLibraryServiceProvider).addFolder(folder);
    if (added == null || !ref.mounted) return false;
    state = ref.read(localLibraryServiceProvider).folders;
    unawaited(ref.read(localScanProvider.notifier).scan(only: [folder]));
    return true;
  }

  Future<void> remove(String id) async {
    await ref.read(localLibraryServiceProvider).removeFolder(id);
    if (!ref.mounted) return;
    state = ref.read(localLibraryServiceProvider).folders;
  }
}

final localFoldersProvider = NotifierProvider<LocalFoldersNotifier, List<LocalFolder>>(LocalFoldersNotifier.new);

class LocalScanState {
  final bool running;
  final int done;
  final int total;

  /// Folders the last scan could not read, by folder id.
  final Map<String, String> failed;
  final int unreadable;
  final DateTime? finishedAt;

  const LocalScanState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.failed = const {},
    this.unreadable = 0,
    this.finishedAt,
  });

  LocalScanState copyWith({
    bool? running,
    int? done,
    int? total,
    Map<String, String>? failed,
    int? unreadable,
    DateTime? finishedAt,
  }) =>
      LocalScanState(
        running: running ?? this.running,
        done: done ?? this.done,
        total: total ?? this.total,
        failed: failed ?? this.failed,
        unreadable: unreadable ?? this.unreadable,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

/// Runs scans one at a time and reports progress. Keep-alive: a scan started
/// from Settings keeps going when the page is closed.
class LocalScanNotifier extends Notifier<LocalScanState> {
  @override
  LocalScanState build() => const LocalScanState();

  Future<void> scan({List<LocalFolder>? only}) async {
    if (state.running) return;
    final service = ref.read(localLibraryServiceProvider);
    if (service.folders.isEmpty) return;
    state = const LocalScanState(running: true);
    try {
      final summary = await service.scan(
        only: only,
        onProgress: (done, total) {
          if (ref.mounted) state = state.copyWith(done: done, total: total);
        },
      );
      if (!ref.mounted) return;
      state = LocalScanState(
        failed: summary.failedFolders,
        unreadable: summary.unreadable,
        finishedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[LocalLibrary] scan failed: $e');
      if (ref.mounted) state = LocalScanState(failed: {'': '$e'}, finishedAt: DateTime.now());
    }
  }
}

final localScanProvider = NotifierProvider<LocalScanNotifier, LocalScanState>(LocalScanNotifier.new);

/// Songs only on this device, for the Library list.
final localSongsProvider = StreamProvider.autoDispose<List<Song>>(
  (ref) => ref.watch(localLibraryServiceProvider).watchSongs(),
);

/// (files on device, of which already on the server).
final localCountsProvider = StreamProvider.autoDispose<(int, int)>(
  (ref) => ref.watch(localLibraryServiceProvider).watchCounts(),
);

final localSearchProvider = FutureProvider.autoDispose.family<List<Song>, String>(
  (ref, query) => ref.watch(localLibraryServiceProvider).search(query),
);

/// Loads the playback index at start-up, re-matches against the server
/// whenever the library sync finishes, and rescans quietly on launch.
final localLibraryBootstrapProvider = Provider<void>((ref) {
  final service = ref.read(localLibraryServiceProvider);
  unawaited(service.rebuildIndex().catchError((Object e) => debugPrint('[LocalLibrary] index: $e')));
  ref.listen(librarySyncProvider.select((s) => s.syncing), (prev, now) {
    if (prev == true && !now) {
      unawaited(service.rematch().catchError((Object e) => debugPrint('[LocalLibrary] match: $e')));
    }
  });
  if (service.folders.isNotEmpty) {
    Timer(const Duration(seconds: 6), () {
      if (ref.mounted) unawaited(ref.read(localScanProvider.notifier).scan());
    });
  }
});

/// Opens the platform's folder picker. Null when cancelled.
Future<LocalFolder?> pickLocalFolder() async {
  if (!kIsWeb && Platform.isAndroid) return SafFileSource.pickFolder();
  final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a music folder');
  if (path == null) return null;
  final name = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? path;
  return LocalFolder(id: folderIdFor(path), uri: path, name: name);
}
