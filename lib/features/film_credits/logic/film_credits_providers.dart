import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../models/catalog.dart';
import '../../../models/song.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart';
import '../data/film_info.dart';
import 'credit_index.dart';

const _kBody = 'film_infos_body_v1';
const _kEtag = 'film_infos_etag_v1';

/// The server's film facts (year, directors, track lists), cache-first like
/// the catalog. A server without film-credits-v1 (404) or a failure leaves it
/// empty: the pages then show only what the library itself says.
class FilmInfosNotifier extends AsyncNotifier<Map<String, FilmInfo>> {
  @override
  Future<Map<String, FilmInfo>> build() async {
    ref.watch(settingsProvider.select((s) => s.username));
    final cached = HiveBoxes.shuffleCache.get(_kBody) as String?;
    if (cached != null) {
      final infos = await compute(parseFilmInfos, cached);
      Future.microtask(() => _revalidate(infos));
      return infos;
    }
    return await _fetch() ?? const {};
  }

  Future<void> _revalidate(Map<String, FilmInfo> current) async {
    final fresh = await _fetch();
    if (fresh != null && ref.mounted) state = AsyncData(fresh);
  }

  /// The new map, or null when nothing changed or the server has none.
  Future<Map<String, FilmInfo>?> _fetch() async {
    try {
      final box = HiveBoxes.shuffleCache;
      final etag = box.get(_kBody) != null ? box.get(_kEtag) as String? : null;
      final res = await ref.read(shuffleApiServiceProvider).getCreditsFilms(etag: etag);
      if (res == null || res.body.isEmpty) return null;
      final infos = await compute(parseFilmInfos, res.body);
      await box.put(_kBody, res.body);
      await box.put(_kEtag, res.etag);
      return infos;
    } catch (e) {
      debugPrint('[FilmCredits] fetch failed: $e');
      return null;
    }
  }
}

final filmInfosProvider =
    AsyncNotifierProvider<FilmInfosNotifier, Map<String, FilmInfo>>(FilmInfosNotifier.new);

/// Films and people across the library. Rebuilt when the library, the catalog
/// or the film facts change, not on playback.
final creditIndexProvider = Provider<CreditIndex>((ref) {
  final songs = ref.watch(allSongsProvider).asData?.value ?? const <Song>[];
  final catalog = ref.watch(catalogProvider).asData?.value.songs ?? const <String, CatalogSong>{};
  final infos = ref.watch(filmInfosProvider).asData?.value ?? const <String, FilmInfo>{};
  if (songs.isEmpty) return CreditIndex.empty;
  return buildCreditIndex(songs, catalog, infos);
});

/// One film, or null when the library has none by that key.
final filmProvider = Provider.family<FilmEntry?, String>(
    (ref, key) => ref.watch(creditIndexProvider.select((i) => i.films[key])));

/// One person, or null.
final personProvider = Provider.family<PersonEntry?, String>(
    (ref, key) => ref.watch(creditIndexProvider.select((i) => i.people[key])));
