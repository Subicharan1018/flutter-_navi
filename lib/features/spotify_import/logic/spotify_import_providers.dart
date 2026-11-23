import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/spotify_import_api.dart';
import '../data/spotify_import_models.dart';
import 'spotify_parser.dart';

final spotifyImportApiProvider = Provider<SpotifyImportApi>((ref) => SpotifyImportApi(ref.watch(fetchDioProvider)));

/// Opens the system file picker for the Spotify ZIP (or its JSON files) and returns their paths; empty when the
/// user backs out. Overridden in tests. Any type is offered: Android's picker hides files with an odd MIME type.
typedef SpotifyFilePicker = Future<List<String>> Function();

final spotifyFilePickerProvider = Provider<SpotifyFilePicker>(
  (ref) => () async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    return [for (final f in r?.files ?? const <PlatformFile>[]) ?f.path];
  },
);

/// Reads the chosen files off the main isolate. Overridden in tests.
typedef SpotifyParser = Future<SpotifyParseResult> Function(List<String> paths);

final spotifyParserProvider = Provider<SpotifyParser>((ref) => parseSpotifyFiles);

/// How the upload waits before trying a busy page again. Overridden in tests.
final spotifyDelayProvider = Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// A page the server answers "busy" to is tried again this many times in a row, then the run stops (Resume).
const int spotifyBusyRetries = 3;

class SpotifyRun {
  /// The newest Spotify import on the server (null: never imported).
  final SpotifyJob? job;

  /// The first look at the server is done (the screen shows a skeleton until then).
  final bool loaded;

  /// That first look failed (the screen offers Try again).
  final bool loadFailed;
  final bool parsing;
  final bool running;

  /// What the chosen file holds, ready to send.
  final SpotifyParseSummary? parsed;
  final String? error;

  /// Pages sent of pages in all, for the bar while sending.
  final int pagesSent;
  final int pagesTotal;

  const SpotifyRun({
    this.job,
    this.loaded = false,
    this.loadFailed = false,
    this.parsing = false,
    this.running = false,
    this.parsed,
    this.error,
    this.pagesSent = 0,
    this.pagesTotal = 0,
  });

  SpotifyRun copy({
    SpotifyJob? job,
    bool? loaded,
    bool? loadFailed,
    bool? parsing,
    bool? running,
    SpotifyParseSummary? parsed,
    String? error,
    int? pagesSent,
    int? pagesTotal,
    bool clearError = false,
    bool clearParsed = false,
    bool clearJob = false,
  }) => SpotifyRun(
    job: clearJob ? null : (job ?? this.job),
    loaded: loaded ?? this.loaded,
    loadFailed: loadFailed ?? this.loadFailed,
    parsing: parsing ?? this.parsing,
    running: running ?? this.running,
    parsed: clearParsed ? null : (parsed ?? this.parsed),
    error: clearError ? null : (error ?? this.error),
    pagesSent: pagesSent ?? this.pagesSent,
    pagesTotal: pagesTotal ?? this.pagesTotal,
  );

  /// Pages of a chosen file are still waiting to be sent.
  bool get hasFile => parsed != null && pagesSent < pagesTotal;

  /// 0..1 of the plays sent while this file is being sent.
  double? get sendProgress => pagesTotal == 0 ? null : (pagesSent / pagesTotal).clamp(0.0, 1.0);
}

class SpotifyImportController extends Notifier<SpotifyRun> {
  bool _stop = false;

  /// The chosen file's plays, oldest first: kept here (not in [state]) so the screen never rebuilds for them.
  List<List<SpotifyPlay>> _pages = const [];
  int _total = 0;

  @override
  SpotifyRun build() {
    ref.onDispose(() => _stop = true);
    Future.microtask(load);
    return const SpotifyRun();
  }

  Future<void> load() async {
    try {
      final all = await ref.read(spotifyImportApiProvider).jobs();
      if (!ref.mounted) return;
      state = state.copy(job: all.firstOrNull, loaded: true, loadFailed: false, clearError: true);
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = state.copy(loaded: true, loadFailed: true, error: e.message);
    }
  }

  /// Picks the export, reads it in an isolate and keeps only the needed fields. Nothing is sent yet.
  Future<void> choose() async {
    if (state.running || state.parsing) return;
    state = state.copy(clearError: true);
    try {
      final paths = await ref.read(spotifyFilePickerProvider)();
      if (paths.isEmpty || !ref.mounted) return;
      state = state.copy(parsing: true, clearParsed: true);
      final result = await ref.read(spotifyParserProvider)(paths);
      if (!ref.mounted) return;
      _pages = spotifyPages(result.plays);
      _total = result.plays.length;
      state = state.copy(
        parsing: false,
        parsed: result.summary,
        pagesSent: 0,
        pagesTotal: _pages.length,
        error: result.plays.isEmpty ? 'No music plays were found in that file.' : null,
        clearError: result.plays.isNotEmpty,
      );
    } on SpotifyParseException catch (e) {
      if (ref.mounted) state = state.copy(parsing: false, error: e.message, clearParsed: true);
    } catch (_) {
      if (ref.mounted) {
        state = state.copy(parsing: false, error: 'Couldn’t read that file. Try the ZIP from Spotify again.', clearParsed: true);
      }
    }
  }

  /// Sends the chosen file page by page. Starting again after a stop continues from the next page; a page that
  /// is sent twice adds nothing, so a crash between pages loses nothing.
  Future<void> start() async {
    final parsed = state.parsed;
    if (state.running || parsed == null || _pages.isEmpty) return;
    _stop = false;
    state = state.copy(running: true, clearError: true);
    final api = ref.read(spotifyImportApiProvider);
    try {
      var job = await api.create(parsed.format, _total);
      state = state.copy(job: job);
      var busy = 0;
      while (!_stop && state.pagesSent < _pages.length) {
        try {
          job = await api.page(job.id, _pages[state.pagesSent]);
          busy = 0;
        } on OnlineFetchException catch (e) {
          final again = e.busy || e.statusCode == 409 || e.statusCode == 429;
          if (!again || ++busy > spotifyBusyRetries) rethrow;
          await ref.read(spotifyDelayProvider)(Duration(seconds: 3 * busy));
          if (!ref.mounted) return;
          continue;
        }
        if (!ref.mounted) return;
        state = state.copy(job: job, pagesSent: state.pagesSent + 1);
      }
      if (!_stop && state.pagesSent >= _pages.length) {
        job = await api.finish(job.id);
        if (!ref.mounted) return;
        _pages = const [];
        state = state.copy(job: job, clearParsed: true, pagesSent: 0, pagesTotal: 0);
      }
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = state.copy(error: e.message);
    } catch (_) {
      if (ref.mounted) state = state.copy(error: 'The import stopped unexpectedly. Tap Resume to try again.');
    } finally {
      if (ref.mounted) state = state.copy(running: false);
    }
  }

  /// Stops after the page being sent; Resume carries on.
  void pause() => _stop = true;

  /// Forgets the chosen file without sending (or the rest of it).
  void discard() {
    if (state.running) return;
    _pages = const [];
    state = state.copy(clearParsed: true, pagesSent: 0, pagesTotal: 0, clearError: true);
  }

  /// Takes back everything this import added. Returns the plays removed, or null if it failed.
  Future<int?> undo() async {
    final job = state.job;
    if (job == null || state.running) return null;
    try {
      final n = await ref.read(spotifyImportApiProvider).undo(job.id);
      if (ref.mounted) state = state.copy(clearJob: true, clearError: true, loaded: true);
      return n;
    } on OnlineFetchException catch (e) {
      if (ref.mounted) state = state.copy(error: e.message);
      return null;
    }
  }
}

final spotifyImportProvider = NotifierProvider<SpotifyImportController, SpotifyRun>(SpotifyImportController.new);
