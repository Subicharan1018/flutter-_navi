import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import '../models/catalog.dart';
import '../models/song.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

const _kBody = 'catalog_body_v1';
const _kEtag = 'catalog_etag_v1';

CatalogDocument _parse(String body) =>
    CatalogDocument.fromJson((jsonDecode(body) as Map).cast<String, dynamic>());

/// The shuffle server's catalog: language, clean genre, film and composer for
/// every song, plus the browse categories.
///
/// Cache-first: the last copy is shown at once (also offline), then revalidated
/// with its ETag — an unchanged catalog costs one empty 304.
class CatalogNotifier extends AsyncNotifier<CatalogDocument> {
  @override
  Future<CatalogDocument> build() async {
    // A different account sees the same library, but re-check on sign-in.
    ref.watch(settingsProvider.select((s) => s.username));
    final box = HiveBoxes.shuffleCache;
    final cached = box.get(_kBody) as String?;
    if (cached != null) {
      final doc = await compute(_parse, cached);
      Future.microtask(() => refresh(silent: true));
      return doc;
    }
    return await _fetch() ?? CatalogDocument.empty;
  }

  /// Revalidates against the server. [silent] keeps the current data on
  /// screen while checking and on failure.
  Future<void> refresh({bool silent = false}) async {
    try {
      final doc = await _fetch();
      if (doc != null) state = AsyncData(doc);
    } catch (e) {
      debugPrint('[Catalog] refresh failed: $e');
      if (!silent && !state.hasValue) state = AsyncError(e, StackTrace.current);
    }
  }

  /// → the new document, or null when the cached copy is still current.
  Future<CatalogDocument?> _fetch() async {
    final box = HiveBoxes.shuffleCache;
    final api = ref.read(shuffleApiServiceProvider);
    final hasCache = box.get(_kBody) != null;
    final res = await api.getCatalog(etag: hasCache ? box.get(_kEtag) as String? : null);
    if (res == null || res.body.isEmpty) return null;
    final doc = await compute(_parse, res.body);
    await box.put(_kBody, res.body);
    await box.put(_kEtag, res.etag);
    return doc;
  }
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, CatalogDocument>(CatalogNotifier.new);

/// One song's catalog entry, or null while loading / when unknown.
final catalogSongProvider = Provider.family<CatalogSong?, String>((ref, id) {
  return ref.watch(catalogProvider.select((d) => d.asData?.value.songs[id]));
});

/// Library songs in a category, in library order.
final categorySongsProvider = Provider.family<AsyncValue<List<Song>>, CatalogCategory>((ref, category) {
  final doc = ref.watch(catalogProvider);
  final songs = ref.watch(allSongsProvider);
  if (doc.isLoading || songs.isLoading) return const AsyncLoading();
  if (songs.hasError) return AsyncError(songs.error!, songs.stackTrace ?? StackTrace.current);
  final catalog = doc.asData?.value.songs ?? const <String, CatalogSong>{};
  return AsyncData([
    for (final s in songs.asData?.value ?? const <Song>[])
      if (catalog[s.id] case final meta? when category.contains(meta)) s,
  ]);
});

/// A cover to represent a category. Picked at a stable position derived from
/// the category's name, so overlapping categories (Tamil and Melody share most
/// songs) don't all show the same first cover.
final categoryCoverProvider = Provider.family<String?, CatalogCategory>((ref, category) {
  final songs = ref.watch(categorySongsProvider(category)).asData?.value ?? const <Song>[];
  final covers = [for (final s in songs) if (s.coverArt.isNotEmpty) s.coverArt];
  if (covers.isEmpty) return null;
  final seed = category.key.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x7fffffff);
  return covers[seed % covers.length];
});

/// "Tamil · Kuthu / Dance · Beast · 2022" — the details Navidrome's tags
/// usually lack, for headers and info lines. Empty when nothing is known.
String catalogDetailLine(CatalogSong? meta, Song song) {
  final parts = <String>[];
  if (meta != null) {
    final langs = [for (final l in meta.languages) languageNames[l] ?? l.toUpperCase()];
    if (langs.isNotEmpty) parts.add(langs.join(' + '));
    if (meta.genre != null) parts.add(meta.genre!);
    if (meta.film != null && meta.film!.toLowerCase() != song.album.toLowerCase()) parts.add(meta.film!);
  }
  final year = song.year > 0 ? song.year : meta?.year;
  if (year != null && year > 0) parts.add('$year');
  return parts.join(' · ');
}

/// The artist line for a song: its tag, or — when the file has no artist tag
/// and Navidrome filled in "Unknown Artist" — the composer the catalog found.
String displayArtist(Song song, CatalogSong? meta) {
  final a = song.artist.trim();
  final missing = a.isEmpty || a.toLowerCase().replaceAll(RegExp(r'[\[\]]'), '') == 'unknown artist';
  if (!missing) return song.artist;
  return meta?.composer ?? song.artist;
}

/// "A • B • C • D • E" → "A • B • C +2": a credit list of a dozen names is
/// noise in a row; the full list is on the song's page. Splits on the
/// separators Navidrome and file tags use (•, /, ;, " feat. " is left alone).
String shortArtists(String artists, {int max = 3}) {
  final parts = artists.split(RegExp(r'\s*[•/;]\s*')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.length <= max) return artists;
  return '${parts.take(max).join(' • ')} +${parts.length - max}';
}
