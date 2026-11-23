import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../../utils/platform_utils.dart';
import '../../exportify_import/logic/exportify_providers.dart' show exportifyCsvPickerProvider, exportifyMaxBytes;
import '../../moods/logic/flow_mood_actions.dart' show moodAdminProvider;
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/data_queue_api.dart';
import '../data/data_queue_models.dart';

final dataQueueApiProvider = Provider<DataQueueApi>((ref) => DataQueueApi(ref.watch(fetchDioProvider)));

/// Whether the signed-in account is the server's admin (the same answer the mood editor uses). The Data queue
/// entry and screen exist only when this is true; the server answers 404 to anyone else anyway.
final dataQueueAdminProvider = Provider<bool>((ref) => ref.watch(moodAdminProvider).asData?.value == true);

final dataQueueStatusProvider = FutureProvider.autoDispose<QueueStatus>(
  (ref) => ref.watch(dataQueueApiProvider).status(),
  retry: (_, _) => null,
);

final dataQueueHistoryProvider = FutureProvider.autoDispose<List<QueueBatch>>(
  (ref) => ref.watch(dataQueueApiProvider).history(),
  retry: (_, _) => null,
);

/// Saves a downloaded file: true when it was saved (the web build hands it to the browser). Overridden in tests.
typedef QueueFileSaver = Future<bool> Function(String name, Uint8List bytes, String mime);

final dataQueueSaverProvider = Provider<QueueFileSaver>((ref) => (name, bytes, mime) async {
      final path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
      if (kIsWeb) return true; // the browser downloads it; there is no path to report
      if (path == null) return false;
      // Windows (and other desktops) only return the chosen path: the file itself is ours to write.
      if (PlatformUtils.isDesktop) await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(path);
      return true;
    });

class DataQueueActionState {
  /// What is going on right now ("Making the batch…"), null when idle.
  final String? busy;
  final String? error;
  final String? notice;

  /// The newest upload's answer, shown until the screen closes.
  final UploadSummary? result;
  const DataQueueActionState({this.busy, this.error, this.notice, this.result});

  DataQueueActionState copy({String? busy, String? error, String? notice, UploadSummary? result}) =>
      DataQueueActionState(busy: busy, error: error, notice: notice, result: result ?? this.result);
}

class DataQueueActions extends Notifier<DataQueueActionState> {
  @override
  DataQueueActionState build() => const DataQueueActionState();

  Future<T?> _run<T>(String busy, Future<T> Function() body) async {
    if (state.busy != null) return null;
    state = state.copy(busy: busy);
    try {
      final out = await body();
      if (ref.mounted) state = state.copy(); // idle again; the caller adds its notice
      return out;
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = state.copy(error: e.message);
      return null;
    }
  }

  void _refresh() {
    ref.invalidate(dataQueueStatusProvider);
    ref.invalidate(dataQueueHistoryProvider);
  }

  Future<void> makeBatch() async {
    final b = await _run('Making the batch…', () => ref.read(dataQueueApiProvider).makeBatch());
    if (!ref.mounted || state.error != null) return;
    state = state.copy(notice: b == null ? 'Nothing is waiting.' : null);
    _refresh();
  }

  /// Downloads batch [id] as `csv` or `txt` and saves it.
  Future<void> download(int id, String format) async {
    final ok = await _run('Preparing the file…', () async {
      final bytes = await ref.read(dataQueueApiProvider).file(id, format);
      final name = 'navivibe_data_queue_${id.toString().padLeft(2, '0')}.$format';
      return ref.read(dataQueueSaverProvider)(name, bytes, format == 'csv' ? 'text/csv' : 'text/plain');
    });
    if (!ref.mounted || state.error != null) return;
    state = state.copy(notice: ok == true ? 'Saved the $format file.' : null);
  }

  /// Chooses the Exportify CSV and sends it for batch [id].
  Future<void> upload(int id) async {
    final done = await _run('Reading the file…', () async {
      final picked = await ref.read(exportifyCsvPickerProvider)();
      if (picked == null) return false;
      if (picked.bytes.length > exportifyMaxBytes) {
        throw const OnlineFetchException('This file is bigger than 8 MB. Export one playlist at a time.');
      }
      state = state.copy(busy: 'Matching “${picked.name}” and fitting the model…');
      final summary = await ref
          .read(dataQueueApiProvider)
          .upload(id, picked.name, utf8.decode(picked.bytes, allowMalformed: true));
      if (ref.mounted) state = DataQueueActionState(busy: state.busy, result: summary);
      return true;
    });
    if (!ref.mounted) return;
    if (done == true) _refresh();
  }

  Future<void> release(int id) async {
    await _run('Releasing the batch…', () => ref.read(dataQueueApiProvider).release(id));
    if (!ref.mounted || state.error != null) return;
    state = state.copy(notice: 'The songs are waiting again.');
    _refresh();
  }
}

final dataQueueActionsProvider =
    NotifierProvider.autoDispose<DataQueueActions, DataQueueActionState>(DataQueueActions.new);
