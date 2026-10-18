import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/models/recommended_song.dart';
import '../../ai_shuffle/data/repositories/shuffle_exception.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart' show shuffleRepositoryProvider;
import '../../trending/data/trending_models.dart';
import '../../trending/logic/trending_providers.dart' show loadChartSongs, trendingApiProvider;

/// One song on Home's "New in Your Library" shelf.
class DiscoverItem {
  final String songId;
  final String title;
  final String artist;

  /// Why it's here: "New · Hot 100" or "Never played".
  final String reason;
  final bool fromCharts;

  const DiscoverItem({
    required this.songId,
    required this.title,
    required this.artist,
    required this.reason,
    required this.fromCharts,
  });
}

/// The shelf: what the charts just brought in (newest first), then songs
/// you've never played that fit your taste — no song twice.
List<DiscoverItem> mergeDiscover(
  List<ChartArrival> arrivals,
  List<({String id, String title, String artist})> unplayed, {
  int maxNew = 12,
  int max = 24,
}) {
  final seen = <String>{};
  final out = <DiscoverItem>[];
  for (final a in arrivals) {
    if (out.length >= maxNew || !seen.add(a.songId)) continue;
    out.add(DiscoverItem(
      songId: a.songId,
      title: a.title,
      artist: a.artist,
      reason: a.charts.isEmpty ? 'New' : 'New · ${a.charts.first}',
      fromCharts: true,
    ));
  }
  for (final u in unplayed) {
    if (out.length >= max) break;
    if (u.id.isEmpty || !seen.add(u.id)) continue;
    out.add(DiscoverItem(songId: u.id, title: u.title, artist: u.artist, reason: 'Never played', fromCharts: false));
  }
  return out;
}

/// Home's Discover shelf. Either source may fail on its own (the stats server
/// or tg-fetcher can be down); only when both do is it an error.
final discoverProvider = FutureProvider.autoDispose<List<DiscoverItem>>(
  (ref) async {
    final (user, pass) = ref.watch(settingsProvider.select((s) => (s.username, s.password)));
    if (user.isEmpty || pass.isEmpty) return const [];
    Object? firstError;
    Future<T?> attempt<T>(Future<T> Function() f) async {
      try {
        return await f();
      } catch (e) {
        firstError ??= e;
        return null;
      }
    }

    // Both requests run at once.
    final arrivalsF = attempt(() => ref.read(trendingApiProvider).recentlyAdded());
    final discoveryF = attempt(() async {
      try {
        return (await ref.read(shuffleRepositoryProvider).getPredictDiscovery(limit: 24, maxPriorPlays: 0)).songs;
      } on ShuffleEmptyResponse {
        return const <RecommendedSong>[];          // nothing unplayed fits: not an error
      }
    });
    final arrivals = await arrivalsF;
    final discovery = await discoveryF;
    if (arrivals == null && discovery == null) throw firstError!;
    final unplayed = [
      for (final s in discovery ?? const <RecommendedSong>[])
        if (s.navidromeId?.isNotEmpty ?? false) (id: s.navidromeId!, title: s.title, artist: s.artist ?? ''),
    ];
    return mergeDiscover(arrivals ?? const [], unplayed);
  },
  retry: (_, _) => null,
);

final discoverPlayerProvider = Provider<DiscoverPlayer>(DiscoverPlayer.new);

/// Plays the shelf in its order, from the tapped song (or the start).
class DiscoverPlayer {
  final Ref _ref;
  DiscoverPlayer(this._ref);

  Future<bool> play(List<DiscoverItem> items, {DiscoverItem? from, bool shuffle = false}) async {
    if (items.isEmpty) return false;
    final byId = await loadChartSongs(_ref, [for (final i in items) i.songId]);
    final queue = [for (final i in items) if (byId[i.songId] != null) byId[i.songId]!];
    if (queue.isEmpty) return false;
    final player = _ref.read(playerProvider.notifier);
    if (shuffle) {
      await player.playPlaylist(queue, shuffle: true, playlistName: 'New in Your Library');
      return true;
    }
    final start = from == null ? 0 : queue.indexWhere((s) => s.id == from.songId);
    await player.setQueue(queue, start < 0 ? 0 : start, playlistName: 'New in Your Library');
    return true;
  }
}
