import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../../trending/logic/trending_providers.dart' show loadChartSongs;
import '../data/listen_api.dart';
import '../data/listen_models.dart';

/// The shuffle server's personal routes (weekly mix, Flow, taste, month).
final listenApiProvider = Provider<ListenApi>((ref) {
  return ListenApi(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'Listen'));
});

/// Whether there is an account to ask the server with. Watching it makes a
/// provider ask again when the account changes.
bool watchSignedIn(Ref ref) {
  final (user, pass) = ref.watch(settingsProvider.select((s) => (s.username, s.password)));
  return user.isNotEmpty && pass.isNotEmpty;
}

/// Library songs for what the server picked, in the server's order. A pick the
/// library can't load is left out.
Future<List<Song>> songsForPicks(Ref ref, Iterable<String> ids) async {
  final wanted = ids.toList();
  final byId = await loadChartSongs(ref, wanted);
  return [for (final id in wanted) if (byId[id] != null) byId[id]!];
}

final listenSongsProvider = Provider<ListenSongs>(ListenSongs.new);

/// [songsForPicks] for widgets, which hold a WidgetRef rather than a Ref.
class ListenSongs {
  final Ref _ref;
  ListenSongs(this._ref);

  Future<List<Song>> load(Iterable<String> ids) => songsForPicks(_ref, ids);

  Future<List<Song>> loadPicks(List<ListenPick> picks) => load([for (final p in picks) p.songId]);
}
