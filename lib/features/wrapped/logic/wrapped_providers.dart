import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/catalog.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/library_provider.dart';
import '../../ai_shuffle/data/models/listening_history_response.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart';
import '../data/wrapped_story.dart';
import 'wrapped_loader.dart';

class _HiveWrappedStore implements WrappedStore {
  @override
  String? read(String key) => HiveBoxes.prefs.get(key) as String?;
  @override
  Future<void> write(String key, String value) => HiveBoxes.prefs.put(key, value);
}

/// Where a built Wrapped is kept (tests replace it).
final wrappedStoreProvider = Provider<WrappedStore>((ref) => _HiveWrappedStore());

/// The date Wrapped counts the current year from (tests replace it).
final wrappedNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The year's Wrapped in stages (see [watchWrapped]), kept on the device (one key per account and year).
final wrappedProvider = StreamProvider.autoDispose.family<WrappedLoad, int>(retry: (_, _) => null, (ref, year) {
  final repo = ref.watch(shuffleRepositoryProvider);
  final db = ref.read(appDatabaseProvider);
  var catalog = ref.read(catalogProvider);
  ref.listen(catalogProvider, (_, next) => catalog = next); // kept current without starting over
  final (server, user) = ref.watch(settingsProvider.select((s) => (s.serverUrl, s.username)));
  return watchWrapped(
    year: year,
    currentYear: ref.read(wrappedNowProvider)().year,
    storeKey: wrappedStoreKey(server, user, year),
    store: ref.read(wrappedStoreProvider),
    fetchYear: (y) => repo.getYearlyReplay(year: y),
    fetchMonth: (y, m) => repo.getMonthlyReplay(year: y, month: m),
    factsOf: (title, artist) async {
      final song = await resolveLibrarySong(db, title, artist);
      if (song == null) return null;
      final meta = catalog.asData?.value.songs[song.id];
      final codes = meta?.languages ?? const <String>[];
      return SongFacts(
        year: song.year > 0 ? song.year : meta?.year,
        composer: (meta?.composer?.trim().isNotEmpty ?? false) ? meta!.composer : song.composer,
        languages: [for (final c in codes) languageNames[c] ?? c.toUpperCase()],
        mood: meta?.moods.firstOrNull,
        bpm: meta?.bpm,
      );
    },
    endsOf: (y) async {
      // Newest first. The year's first play sits where its plays run out; look either side of that.
      WrappedPlay play(PlayHistoryItem i) => WrappedPlay(title: i.title, artist: i.artist, at: i.playedAtIst);
      final head = await repo.getListeningHistory(limit: 1);
      if (head.items.isEmpty || year != ref.read(wrappedNowProvider)().year) return null;
      final at = (y.totalPlays - 25).clamp(0, head.total).toInt();
      final tail = await repo.getListeningHistory(limit: 50, offset: at);
      return bookends(year, latest: play(head.items.first), around: [for (final i in tail.items) play(i)], reachesEnd: at + tail.items.length >= head.total);
    },
  );
});
