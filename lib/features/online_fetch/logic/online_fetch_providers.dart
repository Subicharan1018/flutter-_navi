import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';

final onlineFetchApiProvider = Provider<OnlineFetchApi>((ref) {
  return OnlineFetchApi(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'OnlineFetch'));
});

/// Whether the signed-in account may search online (the server decides who).
/// Re-asks when the account changes; false while signed out or on any error.
final onlineFetchEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  final (user, pass) = ref.watch(settingsProvider.select((s) => (s.username, s.password)));
  if (user.isEmpty || pass.isEmpty) return false;
  return ref.read(onlineFetchApiProvider).enabled();
});

// ─────────────────────────────────────────────────────────────────────────────
// One search (the sheet that's open)
// ─────────────────────────────────────────────────────────────────────────────

class OnlineSearchState {
  final String query;
  final FetchSearch? search;
  final String? error;
  const OnlineSearchState({this.query = '', this.search, this.error});

  bool get isLoading => error == null && (search == null || search!.isSearching);
}

/// Starts a search and polls it until the results (and the AI check) settle.
/// autoDispose: polling stops when the sheet closes. Every poll loop ends on
/// its own — settled, failed, or [maxWait] reached.
class OnlineSearchController extends Notifier<OnlineSearchState> {
  @visibleForTesting
  static Duration pollEvery = const Duration(milliseconds: 1500);
  static const maxWait = Duration(seconds: 120);

  int _generation = 0;

  @override
  OnlineSearchState build() {
    ref.onDispose(() => _generation++);
    return const OnlineSearchState();
  }

  Future<void> start(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final gen = ++_generation;
    state = OnlineSearchState(query: q);
    final api = ref.read(onlineFetchApiProvider);
    try {
      final id = await api.startSearch(q);
      final deadline = DateTime.now().add(maxWait);
      while (true) {
        await Future<void>.delayed(pollEvery);
        if (!ref.mounted || gen != _generation) return;
        final s = await api.search(id);
        if (!ref.mounted || gen != _generation) return;
        state = OnlineSearchState(query: q, search: s);
        if (s.isSettled) return;
        if (DateTime.now().isAfter(deadline)) {
          // Results already shown stay; only a search that never answered fails.
          if (s.isSearching) {
            state = OnlineSearchState(query: q, error: 'The search took too long. Try again.');
          }
          return;
        }
      }
    } on OnlineFetchException catch (e) {
      if (ref.mounted && gen == _generation) state = OnlineSearchState(query: q, error: e.message);
    }
  }
}

final onlineSearchProvider =
    NotifierProvider.autoDispose<OnlineSearchController, OnlineSearchState>(OnlineSearchController.new);

// ─────────────────────────────────────────────────────────────────────────────
// Downloads (keep running when the sheet closes)
// ─────────────────────────────────────────────────────────────────────────────

/// Downloads started from Search online, by candidate id. Keep-alive so a
/// ~1-minute download keeps being tracked (and lands in the library mirror)
/// after the sheet is closed.
class FetchJobsController extends Notifier<Map<int, FetchJob>> {
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 2);
  static const maxWait = Duration(minutes: 15);

  final _songs = <String, Song>{};

  @override
  Map<int, FetchJob> build() => const {};

  void _put(FetchJob job) => state = {...state, job.candidateId: job};

  /// Starts downloading [candidateId] unless it's already on its way or done.
  Future<void> download(int candidateId) async {
    final existing = state[candidateId];
    if (existing != null && existing.phase != FetchJobPhase.failed) return;
    _put(FetchJob(id: 0, candidateId: candidateId, phase: FetchJobPhase.preparing));
    final api = ref.read(onlineFetchApiProvider);
    try {
      final jobId = await api.startDownload(candidateId);
      final deadline = DateTime.now().add(maxWait);
      while (true) {
        await Future<void>.delayed(pollEvery);
        if (!ref.mounted) return;
        final job = await api.job(jobId);
        if (!ref.mounted) return;
        _put(job);
        if (job.isFinished) {
          if (job.phase == FetchJobPhase.ready && job.songId != null) {
            // Bookkeeping: a failed mirror update must not fail the download.
            unawaited(songFor(job).then((_) {}, onError: (_) {}));
          }
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          _put(FetchJob(
            id: jobId,
            candidateId: candidateId,
            phase: FetchJobPhase.failed,
            error: 'This is taking longer than expected. It may still appear in your library.',
          ));
          return;
        }
      }
    } on OnlineFetchException catch (e) {
      if (ref.mounted) {
        _put(FetchJob(id: 0, candidateId: candidateId, phase: FetchJobPhase.failed, error: e.message));
      }
    }
  }

  /// The library song a finished job produced, mirrored locally on first use.
  Future<Song> songFor(FetchJob job) async {
    final id = job.songId;
    if (id == null) throw const OnlineFetchException('This song isn’t in your library yet.');
    return _songs[id] ??= await mirrorNewSong(ref, id);
  }
}

final fetchJobsProvider = NotifierProvider<FetchJobsController, Map<int, FetchJob>>(FetchJobsController.new);
