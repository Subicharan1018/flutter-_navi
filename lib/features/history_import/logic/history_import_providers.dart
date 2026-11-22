import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/history_import_api.dart';
import '../data/history_import_models.dart';

final historyImportApiProvider = Provider<HistoryImportApi>((ref) => HistoryImportApi(ref.watch(fetchDioProvider)));

/// Where the typed account names and the Last.fm API key are kept between visits: the encrypted auth box.
/// Overridden in tests. The key is sent with each page request and never leaves the device otherwise.
class HistoryCredentialStore {
  const HistoryCredentialStore();

  String read(String key) {
    final v = HiveBoxes.auth.get(key);
    return v is String ? v : '';
  }

  Future<void> write(String key, String value) => HiveBoxes.auth.put(key, value.trim());
}

final historyCredentialStoreProvider = Provider<HistoryCredentialStore>((ref) => const HistoryCredentialStore());

String accountKey(HistorySource s) => 'history_${s.wire}_account';
const String lastFmApiKeyKey = 'history_lastfm_api_key';

/// How the importer waits out a "slow down". Overridden in tests.
final historyDelayProvider = Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// Past this many "wait" answers in a row the run stops and says so; it can be resumed.
const int maxWaitsInARow = 8;

class HistoryRun {
  /// The newest job for this source (null: never imported).
  final HistoryJob? job;
  final bool running;
  final bool loaded;
  final String? error;

  /// Set while waiting out a "slow down": seconds left.
  final int waitingS;
  const HistoryRun({this.job, this.running = false, this.loaded = false, this.error, this.waitingS = 0});

  HistoryRun copy({
    HistoryJob? job,
    bool? running,
    bool? loaded,
    String? error,
    int? waitingS,
    bool clearError = false,
  }) => HistoryRun(
    job: job ?? this.job,
    running: running ?? this.running,
    loaded: loaded ?? this.loaded,
    error: clearError ? null : (error ?? this.error),
    waitingS: waitingS ?? this.waitingS,
  );
}

class HistoryImportController extends Notifier<HistoryRun> {
  HistoryImportController(this.source);
  final HistorySource source;
  bool _stop = false;

  @override
  HistoryRun build() {
    ref.onDispose(() => _stop = true);
    Future.microtask(_load);
    return const HistoryRun();
  }

  Future<void> _load() async {
    try {
      final all = await ref.read(historyImportApiProvider).jobs();
      if (!ref.mounted) return;
      state = state.copy(job: all.where((j) => j.source == source).firstOrNull, loaded: true);
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = state.copy(loaded: true, error: e.message);
    }
  }

  String get savedAccount => ref.read(historyCredentialStoreProvider).read(accountKey(source));
  String get savedKey => ref.read(historyCredentialStoreProvider).read(lastFmApiKeyKey);

  /// Reads pages until the history is done, something needs fixing, or [pause]. Starting again after a stop
  /// (or after the app was closed) resumes from where the server's cursor is.
  Future<void> start({required String account, String apiKey = '', bool full = false}) async {
    if (state.running) return;
    final name = account.trim();
    if (name.isEmpty) {
      state = state.copy(error: 'Enter your ${source.label} username.');
      return;
    }
    if (source == HistorySource.lastfm && !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(apiKey.trim())) {
      state = state.copy(error: 'Enter your Last.fm API key: 32 letters and numbers.');
      return;
    }
    _stop = false;
    state = state.copy(running: true, clearError: true, waitingS: 0);
    final api = ref.read(historyImportApiProvider);
    final store = ref.read(historyCredentialStoreProvider);
    try {
      await store.write(accountKey(source), name);
      if (source == HistorySource.lastfm) await store.write(lastFmApiKeyKey, apiKey);
      var job = await api.create(source, name, full: full);
      state = state.copy(job: job);
      final secret = source == HistorySource.lastfm ? apiKey.trim() : null;
      var waits = 0;
      while (!_stop) {
        final r = await api.step(job.id, secret: secret);
        job = r.job;
        state = state.copy(job: job, clearError: true);
        if (r.fatal) {
          state = state.copy(error: job.error ?? 'This import can’t go on.');
          break;
        }
        if (r.done) break;
        if (r.waitS > 0) {
          if (++waits > maxWaitsInARow) {
            state = state.copy(error: '${source.label} is busy. Tap Resume in a minute.');
            break;
          }
          await _wait(r.waitS);
        } else {
          waits = 0;
        }
      }
    } on OnlineFetchException catch (e) {
      state = state.copy(error: e.message);
    } finally {
      state = state.copy(running: false, waitingS: 0);
    }
  }

  Future<void> _wait(int seconds) async {
    final delay = ref.read(historyDelayProvider);
    for (var left = seconds; left > 0 && !_stop; left--) {
      state = state.copy(waitingS: left);
      await delay(const Duration(seconds: 1));
    }
    state = state.copy(waitingS: 0);
  }

  /// Stops after the page being read; it can be resumed.
  void pause() => _stop = true;

  /// Takes back everything this source's imports added. Returns the plays removed, or null if it failed.
  Future<int?> undo() async {
    final job = state.job;
    if (job == null || state.running) return null;
    try {
      final n = await ref.read(historyImportApiProvider).undo(job.id);
      state = const HistoryRun(loaded: true);
      return n;
    } on OnlineFetchException catch (e) {
      state = state.copy(error: e.message);
      return null;
    }
  }
}

final historyImportProvider = NotifierProvider.family<HistoryImportController, HistoryRun, HistorySource>(
  HistoryImportController.new,
);
