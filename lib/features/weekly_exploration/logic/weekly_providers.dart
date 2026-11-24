import 'dart:async';

import '../../../services/pill_wiring.dart' show announceWeeklyReady;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/download_provider.dart' show connectivityProvider;
import '../../../providers/player_provider.dart';
import '../../listen/logic/listen_providers.dart' show listenSongsProvider;
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/weekly_api.dart';
import '../data/weekly_models.dart';

final weeklyApiProvider = Provider<WeeklyApi>((ref) => WeeklyApi(ref.watch(fetchDioProvider)));

/// How often the page asks again while the server is still making the list.
const Duration kWeeklyBuildPoll = Duration(seconds: 6);

/// The Weekly Exploration page's data: the list, the prefs, and Keep / Not for me with the answer
/// shown at once and put back if the server refuses.
class WeeklyController extends AsyncNotifier<WeeklyExploration> {
  Timer? _poll;

  @override
  Future<WeeklyExploration> build() async {
    ref.onDispose(() => _poll?.cancel());
    final w = await ref.watch(weeklyApiProvider).current();
    _schedule(w);
    return w;
  }

  void _schedule(WeeklyExploration w) {
    _poll?.cancel();
    if (!w.building) return;
    _poll = Timer(kWeeklyBuildPoll, () async {
      try {
        final next = await ref.read(weeklyApiProvider).current();
        if (w.building && !next.building) unawaited(announceWeeklyReady(next.picks.length));
        state = AsyncData(next);
        _schedule(next);
      } catch (_) {
        _schedule(w); // a slow minute: try again, keep what is shown
      }
    });
  }

  /// Fresh data from the server without the page going back to loading (pull to refresh, a night's progress).
  Future<void> refresh() async {
    try {
      final w = await ref.read(weeklyApiProvider).current();
      state = AsyncData(w);
      _schedule(w);
    } catch (_) {}
  }

  WeeklyExploration? get _now => state.asData?.value;

  void _replace(int id, WeeklyPick Function(WeeklyPick) f) {
    final w = _now;
    if (w == null) return;
    state = AsyncData(w.copyWith(picks: [for (final p in w.picks) p.id == id ? f(p) : p]));
  }

  /// Keep. Throws the server's own words when it refuses.
  Future<void> keep(int id) async {
    final before = _now;
    if (before == null) return;
    _replace(id, (p) => p.copyWith(state: PickState.kept, download: DownloadStage.waiting));
    try {
      final (stage, songId) = await ref.read(weeklyApiProvider).keep(id);
      _replace(id, (p) => p.copyWith(download: stage, songId: songId));
      unawaited(refresh());
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Not for me.
  Future<void> skip(int id) async {
    final before = _now;
    if (before == null) return;
    _replace(id, (p) => p.copyWith(state: PickState.skipped));
    try {
      await ref.read(weeklyApiProvider).skip(id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Undo a Not for me (the toast's Undo).
  Future<void> restore(int id) async {
    final before = _now;
    if (before == null) return;
    _replace(id, (p) => p.copyWith(state: PickState.pending));
    try {
      await ref.read(weeklyApiProvider).restore(id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> setEnabled(bool v) async {
    final w = await ref.read(weeklyApiProvider).setPrefs(enabled: v);
    state = AsyncData(w);
    _schedule(w);
    if (v) unawaited(refresh());
  }

  Future<void> setCap(int cap) async {
    final w = _now;
    if (w != null) state = AsyncData(w.copyWith(cap: cap));
    final next = await ref.read(weeklyApiProvider).setPrefs(cap: cap);
    state = AsyncData(next);
  }
}

// No automatic retries: a failed load shows its message and "Try again" at once.
final weeklyExplorationProvider =
    AsyncNotifierProvider.autoDispose<WeeklyController, WeeklyExploration>(WeeklyController.new, retry: (_, _) => null);

/// True when this account may download (so Weekly Exploration is for them) and the build has it.
final weeklyAvailableProvider = Provider.autoDispose<bool>((ref) => ref.watch(onlineFetchEnabledProvider).asData?.value == true);

// ─────────────────────────────────────────────────────────────────────────────
// Settings on this device
// ─────────────────────────────────────────────────────────────────────────────

const _kWifiOnly = 'weekly_exploration_wifi_only';

/// "Wi-Fi only": previews are streamed from Apple's servers, so by default they wait for Wi-Fi.
class WeeklyWifiOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    try {
      return HiveBoxes.prefs.get(_kWifiOnly, defaultValue: true) != false;
    } catch (_) {
      return true;
    }
  }

  void set(bool v) {
    state = v;
    try {
      HiveBoxes.prefs.put(_kWifiOnly, v);
    } catch (_) {}
  }
}

final weeklyWifiOnlyProvider = NotifierProvider<WeeklyWifiOnlyNotifier, bool>(WeeklyWifiOnlyNotifier.new);

/// May a preview stream right now? False on mobile data while "Wi-Fi only" is on. Unknown network counts as yes
/// (a desktop may not report one). Overridden in tests.
final previewNetworkOkProvider = Provider<Future<bool> Function()>((ref) => () async {
      if (!ref.read(weeklyWifiOnlyProvider)) return true;
      try {
        final r = await ref.read(connectivityProvider).checkConnectivity();
        final wifi = r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
        return wifi || !r.contains(ConnectivityResult.mobile);
      } catch (_) {
        return true;
      }
    });

// ─────────────────────────────────────────────────────────────────────────────
// Playing a kept song that has come into the library
// ─────────────────────────────────────────────────────────────────────────────

/// Plays a kept pick from the library. False when the song could not be loaded.
final weeklyLibraryPlayerProvider = Provider<Future<bool> Function(String songId)>((ref) => (songId) async {
      final songs = await ref.read(listenSongsProvider).load([songId]);
      if (songs.isEmpty) return false;
      await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: 'Weekly Exploration');
      return true;
    });
