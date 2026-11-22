import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart' show favoritesProvider;
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'album_picks.dart';

/// Album ids the listener dismissed from "Albums for you".
class HiddenAlbumsNotifier extends Notifier<Set<String>> {
  static const key = 'albumsForYouHidden_v1';

  @override
  Set<String> build() {
    try {
      final v = HiveBoxes.prefs.get(key);
      return v is List ? {for (final e in v) e.toString()} : <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  void hide(String albumId) {
    state = {...state, albumId};
    try {
      HiveBoxes.prefs.put(key, state.toList());
    } catch (_) {}
  }
}

final hiddenAlbumsProvider = NotifierProvider<HiddenAlbumsNotifier, Set<String>>(HiddenAlbumsNotifier.new);

/// How many favourite albums are looked into per refresh: each costs one
/// request, so the shelf stays cheap.
const albumsForYouLookups = 14;

/// Albums where you love a few songs and haven't heard the rest. Candidates
/// come from the albums of your favourite songs (those are the albums you
/// already care about); each is opened once to see which songs you never
/// played. Fails soft: any error is an empty shelf, not an error on Home.
final albumsForYouProvider = FutureProvider.autoDispose<List<AlbumPick>>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (settings.serverUrl.isEmpty || settings.password.isEmpty) return const [];
  try {
    final service = ref.watch(subsonicServiceProvider);
    final favs = await ref.watch(favoritesProvider.future);
    final byAlbum = <String, int>{};
    for (final s in favs.songs) {
      if (s.albumId.isNotEmpty) byAlbum[s.albumId] = (byAlbum[s.albumId] ?? 0) + 1;
    }
    final hidden = ref.watch(hiddenAlbumsProvider);
    // Albums with the fewest starred songs first: one or two loved songs is the case.
    final ids = (byAlbum.entries.where((e) => !hidden.contains(e.key)).toList()
          ..sort((a, b) => a.value.compareTo(b.value)))
        .map((e) => e.key)
        .toList();
    ids.shuffle(Random(DateTime.now().day)); // varies by day, steady within one
    final looked = <AlbumCandidate>[];
    for (final id in ids.take(albumsForYouLookups)) {
      try {
        final d = await service.getAlbumDetails(id);
        // getAlbumDetails does not echo star state on songs of other albums;
        // mark the favourites we already know.
        final starredIds = {for (final s in favs.songs) s.id};
        looked.add(AlbumCandidate(
          d.album,
          [for (final s in d.songs) starredIds.contains(s.id) && !s.starred ? s.copyWith(starred: true) : s],
        ));
      } catch (_) {}
    }
    return albumsForYou(looked, hidden: hidden);
  } catch (_) {
    return const [];
  }
});

/// Plays [songs] album by album, albums in random order.
Future<void> playShuffledByAlbum(WidgetRef ref, List<Song> songs, {String? name}) {
  final ordered = shuffleByAlbum(songs, Random());
  return ref.read(playerProvider.notifier).setQueue(ordered, 0, playlistName: name, unshuffledSongs: ordered);
}
