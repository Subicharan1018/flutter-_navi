import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/player_provider.dart';
import '../../online_fetch/logic/fetch_playlists.dart' show fetchPlaylistStoreProvider, upsertFetchPlaylist;
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';

/// Home's and the page's weekly mix. The server keeps one per week (new every
/// Monday 06:00 IST), so there is nothing to poll; pull to refresh re-reads it.
final weeklyMixProvider = FutureProvider.autoDispose<WeeklyMix>(
  (ref) async {
    if (!watchSignedIn(ref)) return const WeeklyMix(items: []);
    return ref.read(listenApiProvider).weeklyMix();
  },
  retry: (_, _) => null,
);

const String weeklyMixPlaylistPrefix = 'Weekly Mix';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "19 Oct": the week a mix belongs to.
String weekLabel(DateTime? weekOf) => weekOf == null ? '' : '${weekOf.day} ${_months[weekOf.month - 1]}';

/// "Weekly Mix · 19 Oct": the playlist a saved mix becomes.
String weeklyMixPlaylistName(WeeklyMix mix) {
  final label = weekLabel(mix.weekOf);
  return label.isEmpty ? weeklyMixPlaylistPrefix : '$weeklyMixPlaylistPrefix · $label';
}

final weeklyMixPlayerProvider = Provider<WeeklyMixPlayer>(WeeklyMixPlayer.new);

class WeeklyMixPlayer {
  final Ref _ref;
  WeeklyMixPlayer(this._ref);

  /// Plays the mix from the tapped song (or the top). False when none of its
  /// songs could be loaded.
  Future<bool> play(WeeklyMix mix, {ListenPick? from, bool shuffle = false}) async {
    final songs = await _ref.read(listenSongsProvider).loadPicks(mix.items);
    if (songs.isEmpty) return false;
    final player = _ref.read(playerProvider.notifier);
    const name = 'Weekly Mix';
    if (shuffle) {
      await player.playPlaylist(songs, shuffle: true, playlistName: name);
      return true;
    }
    final start = from == null ? 0 : songs.indexWhere((s) => s.id == from.songId);
    await player.setQueue(songs, start < 0 ? 0 : start, playlistName: name);
    return true;
  }

  /// Saves the mix as the playlist "Weekly Mix · 19 Oct". Saving the same week
  /// again adds only what's missing. Returns the playlist's name.
  Future<String> saveAsPlaylist(WeeklyMix mix) async {
    final name = weeklyMixPlaylistName(mix);
    await upsertFetchPlaylist(_ref.read(fetchPlaylistStoreProvider), name, [for (final p in mix.items) p.songId]);
    return name;
  }
}
