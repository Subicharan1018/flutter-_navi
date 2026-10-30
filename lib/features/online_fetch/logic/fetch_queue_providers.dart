import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fetch_models.dart';
import '../data/fetch_queue_models.dart';
import '../data/online_fetch_api.dart';
import 'online_fetch_providers.dart';

/// The download queue, refreshed while the queue sheet is open (autoDispose:
/// the timer stops with it). A failed refresh keeps the last list on screen
/// and only the first load shows an error.
class FetchQueueController extends AsyncNotifier<FetchQueue> {
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 3);

  @override
  Future<FetchQueue> build() async {
    final timer = Timer.periodic(pollEvery, (_) => unawaited(_refresh()));
    ref.onDispose(timer.cancel);
    return ref.read(onlineFetchApiProvider).queue();
  }

  Future<void> _refresh() async {
    try {
      final next = await ref.read(onlineFetchApiProvider).queue();
      if (ref.mounted) state = AsyncData(next);
    } catch (_) {
      // Keep what's shown; the next tick tries again.
    }
  }

  /// Runs a queue action, then shows the new queue at once. Returns the
  /// server's message when it refused (e.g. already finished), else null.
  Future<String?> _act(Future<void> Function(OnlineFetchApi api) call) async {
    String? problem;
    try {
      await call(ref.read(onlineFetchApiProvider));
    } on OnlineFetchException catch (e) {
      problem = e.message;
    }
    await _refresh();
    return problem;
  }

  Future<String?> cancel(int id) => _act((api) => api.cancelBatch(id));
  Future<String?> retry(int id) => _act((api) => api.retryBatch(id));
  Future<String?> moveToTop(int id) => _act((api) => api.moveBatchToTop(id));
}

/// Puts a whole playlist link on the download queue in one go: the server
/// lists its songs, then the whole playlist is queued (owned songs are
/// skipped there). Returns null when queued, else a sentence for the user.
Future<String?> queuePlaylistLink(
  OnlineFetchApi api,
  String link, {
  Duration pollEvery = const Duration(milliseconds: 1500),
  int maxPolls = 60,
}) async {
  try {
    final id = await api.startLinkSearch(link);
    for (var i = 0; i < maxPolls; i++) {
      await Future<void>.delayed(pollEvery);
      final s = await api.search(id);
      if (s.isSearching) continue;
      if (s.status == FetchSearchStatus.failed) return s.error ?? 'Couldn’t read that playlist.';
      if (s.candidates.isEmpty) return 'That playlist has no songs.';
      await api.startLinkBatch(id);
      return null;
    }
    return 'The playlist took too long to load. Try again.';
  } on OnlineFetchException catch (e) {
    return e.message;
  }
}

final fetchQueueProvider =
    AsyncNotifierProvider.autoDispose<FetchQueueController, FetchQueue>(FetchQueueController.new);
