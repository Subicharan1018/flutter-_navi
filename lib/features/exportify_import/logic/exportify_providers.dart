import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../../online_fetch/logic/fetch_playlists.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/exportify_api.dart';
import '../data/exportify_models.dart';

final exportifyApiProvider = Provider<ExportifyApi>((ref) => ExportifyApi(ref.watch(fetchDioProvider)));

/// The server's limit on the file (8 MB); a bigger one is refused here without being sent.
const int exportifyMaxBytes = 8000000;

/// A chosen file: its name and its bytes.
class PickedCsv {
  final String name;
  final List<int> bytes;
  const PickedCsv(this.name, this.bytes);
}

/// Opens the system file picker for the Exportify CSV. Null when the user backs out.
/// Overridden in tests. Any file type is offered: Android's picker hides a CSV that
/// carries another MIME type (many do), and the server says plainly when a file isn't one.
typedef CsvPicker = Future<PickedCsv?> Function();

final exportifyCsvPickerProvider = Provider<CsvPicker>((ref) => () async {
      final r = await FilePicker.platform.pickFiles(withData: true);
      final f = r?.files.firstOrNull;
      if (f == null) return null;
      final bytes = f.bytes;
      if (bytes == null) throw const OnlineFetchException('Couldn’t read that file. Try another one.');
      return PickedCsv(f.name, bytes);
    });

/// The user's imports, newest first.
final exportifyImportsProvider = FutureProvider.autoDispose<List<ExportifySummary>>((ref) async {
  final all = await ref.watch(exportifyApiProvider).imports();
  // Weekly Exploration keeps its kept songs in one import of its own so the same night fetch downloads
  // them; it has a page of its own, so it is not listed as a playlist import.
  // Album Overnight does the same (tgfetch/album_overnight.py): its page is Settings › Album Overnight.
  return [for (final s in all) if (s.name != kWeeklyExplorationImportName && s.name != kAlbumOvernightImportName) s];
}, retry: (_, _) => null);

/// The name of the import the server keeps Album Overnight's queued tracks in (tgfetch/album_overnight.py).
const String kAlbumOvernightImportName = 'Album Overnight';

/// The name of the import the server keeps Weekly Exploration's kept songs in (tgfetch/weekly_exploration.py).
const String kWeeklyExplorationImportName = 'Weekly Exploration';

// ─────────────────────────────────────────────────────────────────────────────
// Choosing and uploading the file
// ─────────────────────────────────────────────────────────────────────────────

class ExportifyUploadState {
  /// The file being read and matched, while that goes on.
  final String? busyName;
  final String? error;
  const ExportifyUploadState({this.busyName, this.error});

  bool get busy => busyName != null;
}

class ExportifyUploadController extends Notifier<ExportifyUploadState> {
  @override
  ExportifyUploadState build() => const ExportifyUploadState();

  /// Picks a file and sends it. Returns the import, or null when nothing was chosen or it failed
  /// (then [ExportifyUploadState.error] says why).
  Future<ExportifySummary?> pickAndUpload() async {
    if (state.busy) return null;
    try {
      final picked = await ref.read(exportifyCsvPickerProvider)();
      if (picked == null) return null;
      if (picked.bytes.length > exportifyMaxBytes) {
        state = const ExportifyUploadState(
          error: 'This file is bigger than 8 MB. Export one playlist at a time.',
        );
        return null;
      }
      state = ExportifyUploadState(busyName: picked.name);
      final summary = await ref.read(exportifyApiProvider).createImport(
            picked.name,
            utf8.decode(picked.bytes, allowMalformed: true),
          );
      if (!ref.mounted) return summary;
      state = const ExportifyUploadState();
      ref.invalidate(exportifyImportsProvider);
      return summary;
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = ExportifyUploadState(error: e.message);
      return null;
    }
  }
}

final exportifyUploadProvider =
    NotifierProvider.autoDispose<ExportifyUploadController, ExportifyUploadState>(ExportifyUploadController.new);

// ─────────────────────────────────────────────────────────────────────────────
// One import, refreshed while its screen is open
// ─────────────────────────────────────────────────────────────────────────────

class ExportifyDetail extends AsyncNotifier<ExportifySummary> {
  final int id;
  ExportifyDetail(this.id);

  static Duration pollEvery = const Duration(seconds: 5);

  @override
  Future<ExportifySummary> build() async {
    final timer = Timer.periodic(pollEvery, (_) => unawaited(_refresh()));
    ref.onDispose(timer.cancel);
    return ref.read(exportifyApiProvider).importById(id);
  }

  /// A failed refresh keeps what is on screen; only the first load shows an error.
  Future<void> _refresh() async {
    try {
      final next = await ref.read(exportifyApiProvider).importById(id);
      if (ref.mounted) state = AsyncData(next);
    } catch (_) {}
  }

  /// Runs an action and shows its result at once. Returns the server's sentence when it refused.
  Future<String?> _act(Future<ExportifySummary?> Function(ExportifyApi api) call) async {
    try {
      final next = await call(ref.read(exportifyApiProvider));
      if (ref.mounted && next != null) state = AsyncData(next);
      return null;
    } on OnlineFetchException catch (e) {
      return e.message;
    }
  }

  Future<String?> start(PlanDraft draft) => _act((api) => api.start(id, draft));
  Future<String?> pause() => _act((api) => api.pause(id));
  Future<String?> cancel() => _act((api) => api.cancel(id));
  Future<String?> savePlan(PlanDraft draft) => _act((api) => api.savePlan(id, draft));

  Future<String?> retryFailed() async {
    final problem = await _act((api) async {
      await api.retryFailed(id);
      return api.importById(id);
    });
    if (ref.mounted) ref.invalidate(exportifyFailedProvider(id));
    return problem;
  }
}

final exportifyDetailProvider = AsyncNotifierProvider.autoDispose.family<ExportifyDetail, ExportifySummary, int>(
  ExportifyDetail.new,
  retry: (_, _) => null,
);

/// What fetching would cost with these settings (asked again when they change).
final exportifyEstimateProvider = FutureProvider.autoDispose.family<ExportifyEstimate, (int, PlanDraft)>(
  (ref, key) => ref.watch(exportifyApiProvider).estimate(key.$1, key.$2),
  retry: (_, _) => null,
);

/// The songs that failed, with why (the first 200).
final exportifyFailedProvider = FutureProvider.autoDispose.family<List<ExportifySong>, int>(
  (ref, id) => ref.watch(exportifyApiProvider).songs(id, WishlistState.failed),
  retry: (_, _) => null,
);

// ─────────────────────────────────────────────────────────────────────────────
// A playlist of the songs already in the library
// ─────────────────────────────────────────────────────────────────────────────

/// Makes the user's playlist (named after the file) from the songs the import found in the
/// library, in the file's order, and remembers it on the server. Asked again, it only adds songs
/// that arrived since. Returns the playlist id.
final exportifyPlaylistMakerProvider =
    Provider<Future<String> Function(ExportifySummary)>((ref) => (imp) => _makeLibraryPlaylist(ref, imp));

Future<String> _makeLibraryPlaylist(Ref ref, ExportifySummary imp) async {
  final api = ref.read(exportifyApiProvider);
  final ids = imp.ownedIds.isNotEmpty ? imp.ownedIds : await api.ownedIds(imp.id);
  if (ids.isEmpty) throw const OnlineFetchException('None of these songs are in your library yet.');
  final playlistId = await upsertFetchPlaylist(ref.read(fetchPlaylistStoreProvider), imp.name, ids);
  try {
    await api.setPlaylist(imp.id, playlistId);
  } catch (_) {
    // Only bookkeeping: the playlist exists either way.
  }
  ref.invalidate(exportifyImportsProvider);
  ref.invalidate(exportifyDetailProvider(imp.id));
  return playlistId;
}
