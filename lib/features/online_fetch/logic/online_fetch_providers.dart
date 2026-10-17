import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import 'fetch_playlists.dart';

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
  final FetchSearchType type;
  final FetchSearch? search;
  final String? error;

  /// Set while showing an artist result's top songs; [parent] is the artist
  /// search to go back to.
  final FetchCandidate? artist;
  final OnlineSearchState? parent;

  const OnlineSearchState({
    this.query = '',
    this.type = FetchSearchType.song,
    this.search,
    this.error,
    this.artist,
    this.parent,
  });

  bool get isLoading => error == null && (search == null || search!.isSearching);

  /// The results are songs (a song search, or an artist's top songs), so
  /// several can be picked at once.
  bool get listsSongs => type == FetchSearchType.song || artist != null;

  OnlineSearchState withResult({FetchSearch? search, String? error}) => OnlineSearchState(
        query: query,
        type: type,
        search: search,
        error: error,
        artist: artist,
        parent: parent,
      );
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

  Future<void> start(String query, {FetchSearchType type = FetchSearchType.song}) async {
    final q = query.trim();
    if (q.length < 2) return;
    final api = ref.read(onlineFetchApiProvider);
    await _run(OnlineSearchState(query: q, type: type), () => api.startSearch(q, type: type));
  }

  /// Shows [artist]'s top songs; [back] returns to the artist results.
  Future<void> openArtist(FetchCandidate artist) async {
    final api = ref.read(onlineFetchApiProvider);
    await _run(
      OnlineSearchState(query: artist.title, artist: artist, parent: state),
      () => api.startArtistSongs(artist.id),
    );
  }

  void back() {
    final parent = state.parent;
    if (parent == null) return;
    _generation++;
    state = parent;
  }

  Future<void> _run(OnlineSearchState base, Future<int> Function() create) async {
    final gen = ++_generation;
    state = base;
    final api = ref.read(onlineFetchApiProvider);
    try {
      final id = await create();
      final deadline = DateTime.now().add(maxWait);
      while (true) {
        await Future<void>.delayed(pollEvery);
        if (!ref.mounted || gen != _generation) return;
        final s = await api.search(id);
        if (!ref.mounted || gen != _generation) return;
        state = base.withResult(search: s);
        if (s.isSettled) return;
        if (DateTime.now().isAfter(deadline)) {
          // Results already shown stay; only a search that never answered fails.
          if (s.isSearching) state = base.withResult(error: 'The search took too long. Try again.');
          return;
        }
      }
    } on OnlineFetchException catch (e) {
      if (ref.mounted && gen == _generation) state = base.withResult(error: e.message);
    }
  }
}

final onlineSearchProvider =
    NotifierProvider.autoDispose<OnlineSearchController, OnlineSearchState>(OnlineSearchController.new);

// ─────────────────────────────────────────────────────────────────────────────
// Downloads (keep running when the sheet closes; followed app-wide)
// ─────────────────────────────────────────────────────────────────────────────

/// Everything downloading or downloaded from Search online this session:
/// single songs by result id, and batches (several songs, an album, a
/// playlist) in the order they were started.
class FetchDownloads {
  final Map<int, FetchJob> jobs;
  final Map<int, FetchBatch> batches;

  const FetchDownloads({this.jobs = const {}, this.batches = const {}});

  /// The newest batch [candidateId] was picked into (an album row's progress).
  FetchBatch? batchFor(int candidateId) =>
      batches.values.where((b) => b.candidateIds.contains(candidateId)).lastOrNull;

  /// A song result's download: on its own, or as one of a batch's songs.
  FetchJob? jobFor(int candidateId) {
    final own = jobs[candidateId];
    if (own != null) return own;
    for (final b in batches.values.toList().reversed) {
      for (final item in b.items) {
        if (item.candidateId == candidateId) return item;
      }
      // Picked, but the server hasn't listed the batch's songs yet.
      if (!b.isFinished && b.kind == null && b.candidateIds.contains(candidateId)) {
        return FetchJob(id: 0, candidateId: candidateId, phase: FetchJobPhase.preparing);
      }
    }
    return null;
  }

  Iterable<FetchJob> get _activeJobs => jobs.values.where((j) => !j.isFinished);
  Iterable<FetchBatch> get _activeBatches => batches.values.where((b) => !b.isFinished);

  /// Songs and batches still on their way.
  int get activeCount => _activeJobs.length + _activeBatches.length;
  bool get isActive => activeCount > 0;
  bool get isEmpty => jobs.isEmpty && batches.isEmpty;

  /// Overall progress (0–1) of everything still on its way, or null when
  /// nothing has measurable progress yet (show an indeterminate ring).
  double? get progress {
    final parts = [
      for (final j in _activeJobs) jobProgress(j),
      for (final b in _activeBatches) b.progress,
    ];
    if (parts.isEmpty) return null;
    final p = parts.reduce((a, b) => a + b) / parts.length;
    return p > 0 ? p : null;
  }

  /// One song's share of the way: downloading is most of the wait.
  static double jobProgress(FetchJob j) => switch (j.phase) {
        FetchJobPhase.preparing => 0,
        FetchJobPhase.downloading => j.progress * 0.9,
        FetchJobPhase.adding => 0.9,
        _ => 1,
      };
}

/// A download that just finished, for the app-wide pop-up. [seq] makes each
/// one distinct even when the text repeats.
class FetchFinished {
  final int seq;
  final String headline;
  final String detail;
  final String? coverUrl;

  /// The library songs to play / add to a playlist (empty when nothing landed).
  final List<String> songIds;
  const FetchFinished({
    required this.seq,
    required this.headline,
    required this.detail,
    this.coverUrl,
    this.songIds = const [],
  });
}

class FetchFinishedNotifier extends Notifier<FetchFinished?> {
  int _seq = 0;

  @override
  FetchFinished? build() => null;

  void announce({required String headline, required String detail, String? coverUrl, List<String> songIds = const []}) =>
      state = FetchFinished(seq: ++_seq, headline: headline, detail: detail, coverUrl: coverUrl, songIds: songIds);

  void dismiss() => state = null;
}

final fetchFinishedProvider = NotifierProvider<FetchFinishedNotifier, FetchFinished?>(FetchFinishedNotifier.new);

/// Downloads started from Search online. Keep-alive so a download keeps being
/// tracked (and lands in the library mirror) after the sheet is closed; every
/// finished one is announced through [fetchFinishedProvider].
class FetchJobsController extends Notifier<FetchDownloads> {
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 2);

  /// Give up following a download that hasn't changed for this long.
  static const stallLimit = Duration(minutes: 15);

  /// Poll failures in a row (offline, rate limited) before a download is
  /// shown as failed; one bad poll never fails it.
  static const maxPollErrors = 5;

  final _songs = <String, Song>{};
  final _cover = <int, String?>{};
  int _nextBatchKey = 0;
  bool _resumed = false;

  @override
  FetchDownloads build() => const FetchDownloads();

  void _putJob(FetchJob job) =>
      state = FetchDownloads(jobs: {...state.jobs, job.candidateId: job}, batches: state.batches);

  void _putBatch(int key, FetchBatch b) =>
      state = FetchDownloads(jobs: state.jobs, batches: {...state.batches, key: b});

  /// Each running download polls on its own; spread them out so several at
  /// once stay inside the server's rate limit.
  Duration get _interval => pollEvery * (state.activeCount < 1 ? 1 : state.activeCount);

  /// Starts downloading one song unless it's already on its way or done.
  Future<void> download(int candidateId, {String? coverUrl}) async {
    final existing = state.jobFor(candidateId);
    if (existing != null && existing.phase != FetchJobPhase.failed) return;
    _cover[candidateId] = coverUrl;
    _putJob(FetchJob(id: 0, candidateId: candidateId, phase: FetchJobPhase.preparing));
    final api = ref.read(onlineFetchApiProvider);
    final int jobId;
    try {
      jobId = await api.startDownload(candidateId);
    } on OnlineFetchException catch (e) {
      if (ref.mounted) _putJob(FetchJob(id: 0, candidateId: candidateId, phase: FetchJobPhase.failed, error: e.message));
      return;
    }
    final job = await _follow<FetchJob>(
      () => api.job(jobId),
      (j) => _putJob(j),
      isFinished: (j) => j.isFinished,
      onGiveUp: (message) => FetchJob(id: jobId, candidateId: candidateId, phase: FetchJobPhase.failed, error: message),
    );
    if (job != null) _announceJob(job);
  }

  /// Downloads [picks] together: several songs, or whole albums / playlists /
  /// an artist's top songs, as one batch with overall progress. Owned songs
  /// are left out; one song alone is a plain download.
  Future<void> downloadAll(List<FetchCandidate> picks) async {
    final wanted = [
      for (final c in picks)
        if (!(c.isSong && c.inLibrary)) c,
    ];
    if (wanted.isEmpty) return;
    if (wanted.length == 1 && wanted.single.isSong) return download(wanted.single.id, coverUrl: wanted.single.coverUrl);
    final ids = [for (final c in wanted) c.id];
    if (ids.every((id) => state.batchFor(id)?.isFinished == false)) return;   // already on its way

    final one = wanted.length == 1 ? wanted.single : null;
    final key = ++_nextBatchKey;
    var batch = FetchBatch(
      id: 0,
      candidateIds: ids,
      kind: one?.type,
      title: one?.title ?? '${ids.length} songs',
      artist: one?.artist ?? '',
      coverUrl: (one ?? wanted.first).coverUrl,
    );
    _putBatch(key, batch);
    final api = ref.read(onlineFetchApiProvider);
    try {
      final id = await api.startBatch(ids);
      batch = batch.copyWith(id: id);
      if (ref.mounted) _putBatch(key, batch);
    } on OnlineFetchException catch (e) {
      if (ref.mounted) _putBatch(key, _failed(batch, e.message));
      return;
    }
    await _followBatch(key, batch);
  }

  /// Picks up batches still running on the server (e.g. after the app was
  /// restarted mid-album). Once per session; any failure is ignored.
  Future<void> resume() async {
    if (_resumed) return;
    _resumed = true;
    try {
      final api = ref.read(onlineFetchApiProvider);
      final recent = await api.recentBatches();
      for (final b in recent.where((b) => !b.isFinished || b.needsPlaylist)) {
        if (!ref.mounted || state.batches.values.any((x) => x.id == b.id)) continue;
        final key = ++_nextBatchKey;
        if (b.isFinished) {
          // Finished while the app was closed: make its playlist now.
          final full = await api.batch(b.id);
          if (!ref.mounted) return;
          _putBatch(key, full);
          await _finishBatch(key, full);
        } else {
          _putBatch(key, b);
          unawaited(_followBatch(key, b));
        }
      }
    } catch (_) {
      // Bookkeeping: the app works the same without it.
    }
  }

  /// The album art shown with a single song's result, if any.
  String? coverFor(int candidateId) => _cover[candidateId];

  /// Forgets finished downloads (the Downloads list's Clear).
  void clearFinished() => state = FetchDownloads(
        jobs: {for (final e in state.jobs.entries) if (!e.value.isFinished) e.key: e.value},
        batches: {for (final e in state.batches.entries) if (!e.value.isFinished) e.key: e.value},
      );

  Future<void> _followBatch(int key, FetchBatch start) async {
    final api = ref.read(onlineFetchApiProvider);
    final b = await _follow<FetchBatch>(
      () => api.batch(start.id),
      (b) => _putBatch(key, b),
      isFinished: (b) => b.isFinished,
      onGiveUp: (message) => _failed(state.batches[key] ?? start, message),
    );
    if (b == null) return;
    await _finishBatch(key, b);
  }

  Future<void> _finishBatch(int key, FetchBatch b) async {
    if (b.status != FetchBatchStatus.done) {
      _finished.announce(headline: 'Couldn’t download ${b.title}', detail: b.error ?? 'Try again in a moment.', coverUrl: b.coverUrl);
      return;
    }
    final added = [for (final i in b.items) if (i.phase == FetchJobPhase.ready && i.songId != null) i.songId!];
    // Bookkeeping: a failed mirror update must not fail the download.
    if (added.isNotEmpty) unawaited(songsFor(added).then((_) {}, onError: (_) {}));
    if (b.needsPlaylist && !await _makePlaylist(key, b)) {
      _finished.announce(
        headline: 'Playlist downloaded',
        detail: 'Couldn’t make the playlist yet. It’s tried again next time the app opens.',
        coverUrl: b.coverUrl,
        songIds: b.songIds,
      );
      return;
    }
    _finished.announce(headline: b.headline, detail: b.summary, coverUrl: b.coverUrl, songIds: b.songIds);
  }

  /// The bot playlist becomes the user's own playlist, in the bot's order,
  /// owned and downloaded songs alike; the server remembers it was made.
  Future<bool> _makePlaylist(int key, FetchBatch b) async {
    if (b.songIds.isEmpty) return true;          // nothing to make it from
    try {
      final id = await upsertFetchPlaylist(ref.read(fetchPlaylistStoreProvider), b.title, b.songIds);
      await ref.read(onlineFetchApiProvider).setBatchPlaylist(b.id, id);
      if (ref.mounted) _putBatch(key, b.copyWith(playlistId: id));
      return true;
    } catch (_) {
      return false;
    }
  }

  static FetchBatch _failed(FetchBatch b, String message) =>
      b.copyWith(status: FetchBatchStatus.failed, error: message);

  /// Polls [fetch] until [isFinished]; every answer goes to [put]. Returns
  /// the finished value, the [onGiveUp] value after too many failed polls or
  /// a stall, or null when the app shut down.
  Future<T?> _follow<T>(
    Future<T> Function() fetch,
    void Function(T) put, {
    required bool Function(T) isFinished,
    required T Function(String message) onGiveUp,
  }) async {
    var errors = 0;
    var lastChange = DateTime.now();
    String? lastSeen;
    while (true) {
      await Future<void>.delayed(_interval);
      if (!ref.mounted) return null;
      T value;
      try {
        value = await fetch();
        errors = 0;
      } on OnlineFetchException catch (e) {
        if (++errors < maxPollErrors) continue;
        final failed = onGiveUp(e.message);
        if (ref.mounted) put(failed);
        return failed;
      }
      if (!ref.mounted) return null;
      put(value);
      if (isFinished(value)) return value;
      final seen = _fingerprint(value);
      if (seen != lastSeen) {
        lastSeen = seen;
        lastChange = DateTime.now();
      } else if (DateTime.now().difference(lastChange) > stallLimit) {
        final failed = onGiveUp('This is taking longer than expected. It may still appear in your library.');
        put(failed);
        return failed;
      }
    }
  }

  static String _fingerprint(Object? v) => switch (v) {
        FetchJob j => '${j.phase}/${j.progress}',
        FetchBatch b => '${b.status}/${b.progress}/${b.total}',
        _ => '$v',
      };

  FetchFinishedNotifier get _finished => ref.read(fetchFinishedProvider.notifier);

  void _announceJob(FetchJob job) {
    final cover = _cover[job.candidateId];
    final label = [job.title, job.artist].whereType<String>().where((s) => s.isNotEmpty).join(' — ');
    switch (job.phase) {
      case FetchJobPhase.ready:
        // Bookkeeping: a failed mirror update must not fail the download.
        unawaited(songFor(job).then((_) {}, onError: (_) {}));
        _finished.announce(headline: 'Song downloaded', detail: label, coverUrl: cover, songIds: [job.songId!]);
      case FetchJobPhase.duplicate:
        _finished.announce(
          headline: 'Already in your library',
          detail: label,
          coverUrl: cover,
          songIds: [if (job.songId != null) job.songId!],
        );
      case FetchJobPhase.rejected:
        _finished.announce(headline: 'Not available in lossless quality', detail: label, coverUrl: cover);
      case FetchJobPhase.failed:
        _finished.announce(headline: 'Download didn’t finish', detail: job.error ?? label, coverUrl: cover);
      default:
        break;
    }
  }

  /// The library song a finished job produced, mirrored locally on first use.
  Future<Song> songFor(FetchJob job) async {
    final id = job.songId;
    if (id == null) throw const OnlineFetchException('This song isn’t in your library yet.');
    return (await songsFor([id])).single;
  }

  /// Library songs by id, in order, mirrored locally on first use.
  Future<List<Song>> songsFor(List<String> ids) async {
    final missing = [for (final id in ids) if (!_songs.containsKey(id)) id];
    if (missing.isNotEmpty) {
      for (final s in await mirrorNewSongs(ref, missing)) {
        _songs[s.id] = s;
      }
    }
    return [for (final id in ids) if (_songs[id] != null) _songs[id]!];
  }
}

final fetchJobsProvider = NotifierProvider<FetchJobsController, FetchDownloads>(FetchJobsController.new);
