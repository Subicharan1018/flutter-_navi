import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/library_provider.dart' show songFromMetadata;
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../data/trending_api.dart';
import '../data/trending_models.dart';

final trendingApiProvider = Provider<TrendingApi>((ref) {
  return TrendingApi(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'Trending'));
});

/// Today's charts. Re-asks when the account changes; Home and the Trending
/// page both watch it, so it lives while either is on screen. Charts change
/// once a day — pull to refresh re-reads them. No automatic retry: the Dio
/// client already retries, so a failure shows at once with Try again.
final trendingChartsProvider = FutureProvider.autoDispose<TrendingCharts>(
  (ref) async {
    final (user, pass) = ref.watch(settingsProvider.select((s) => (s.username, s.password)));
    if (user.isEmpty || pass.isEmpty) return const TrendingCharts([]);
    return ref.read(trendingApiProvider).charts();
  },
  retry: (_, _) => null,
);

/// The chart picked on Home or the Trending page (null: the first one).
/// Shared, so opening the page from Home shows the same chart.
class SelectedChart extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String key) => state = key;
}

final selectedChartProvider = NotifierProvider<SelectedChart, String?>(SelectedChart.new);

/// The picked chart out of [charts], falling back to the first with songs.
TrendingChart? pickChart(TrendingCharts charts, String? key) {
  final shown = charts.withSongs;
  if (shown.isEmpty) return null;
  return shown.firstWhere((c) => c.key == key, orElse: () => shown.first);
}

/// The chart's playable songs in rank order, given the library songs found
/// for their ids. Entries whose song couldn't be loaded are skipped.
List<Song> chartQueue(TrendingChart chart, Map<String, Song> byId) => [
      for (final e in chart.entries)
        if (e.playable && byId[e.songId] != null) byId[e.songId]!,
    ];

/// Library songs for [ids]: the local mirror first, the server for any the
/// mirror hasn't caught up with yet (a song downloaded this morning).
Future<Map<String, Song>> loadChartSongs(Ref ref, List<String> ids) async {
  final db = ref.read(appDatabaseProvider);
  final found = <String, Song>{};
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    final rows = await (db.select(db.songMetadata)..where((t) => t.songId.isIn(chunk))).get();
    for (final r in rows) {
      found[r.songId] = songFromMetadata(r);
    }
  }
  final missing = [for (final id in ids) if (!found.containsKey(id)) id];
  if (missing.isNotEmpty) {
    for (final s in await ref.read(subsonicServiceProvider).getSongs(missing)) {
      found[s.id] = s;
    }
  }
  return found;
}

/// Plays a chart in rank order, starting at [from] (or the top). Returns
/// false when none of its songs could be loaded.
final chartPlayerProvider = Provider<ChartPlayer>(ChartPlayer.new);

class ChartPlayer {
  final Ref _ref;
  ChartPlayer(this._ref);

  Future<bool> play(TrendingChart chart, {ChartEntry? from, bool shuffle = false}) async {
    final ids = [for (final e in chart.entries) if (e.playable) e.songId!];
    if (ids.isEmpty) return false;
    final queue = chartQueue(chart, await loadChartSongs(_ref, ids));
    if (queue.isEmpty) return false;
    final name = 'Trending: ${chart.title}';
    final player = _ref.read(playerProvider.notifier);
    if (shuffle) {
      await player.playPlaylist(queue, shuffle: true, playlistName: name);
      return true;
    }
    final start = from == null ? 0 : queue.indexWhere((s) => s.id == from.songId);
    await player.setQueue(queue, start < 0 ? 0 : start, playlistName: name);
    return true;
  }
}
