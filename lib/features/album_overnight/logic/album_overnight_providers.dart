import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online_fetch/logic/online_fetch_providers.dart';
import '../data/album_overnight_api.dart';
import '../data/album_overnight_models.dart';

final albumOvernightApiProvider = Provider<AlbumOvernightApi>((ref) => AlbumOvernightApi(ref.watch(fetchDioProvider)));

/// The queue page and the settings rows share this: prefs and the albums, with a cancel shown at once and
/// put back if the server refuses.
class AlbumOvernightController extends AsyncNotifier<AlbumOvernight> {
  @override
  Future<AlbumOvernight> build() => ref.watch(albumOvernightApiProvider).current();

  /// Fresh data from the server without the page going back to loading (pull to refresh, a night's progress).
  Future<void> refresh() async {
    try {
      state = AsyncData(await ref.read(albumOvernightApiProvider).current());
    } catch (_) {}
  }

  AlbumOvernight? get _now => state.asData?.value;

  Future<void> _prefs({bool? enabled, bool? filmOnly, int? perNight, int? maxPerAlbum}) async {
    final before = _now;
    if (before != null) {
      state = AsyncData(before.copyWith(enabled: enabled, filmOnly: filmOnly, perNight: perNight, maxPerAlbum: maxPerAlbum));
    }
    try {
      state = AsyncData(await ref
          .read(albumOvernightApiProvider)
          .setPrefs(enabled: enabled, filmOnly: filmOnly, perNight: perNight, maxPerAlbum: maxPerAlbum));
    } catch (_) {
      if (before != null) state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> setEnabled(bool v) => _prefs(enabled: v);
  Future<void> setFilmOnly(bool v) => _prefs(filmOnly: v);
  Future<void> setPerNight(int v) => _prefs(perNight: v);
  Future<void> setMaxPerAlbum(int v) => _prefs(maxPerAlbum: v);

  /// Cancel one album. Throws the server's own words when it refuses.
  Future<CancelResult> cancelAlbum(int id) async {
    final before = _now;
    if (before != null) state = AsyncData(before.copyWith(albums: [for (final a in before.albums) if (a.id != id) a]));
    try {
      final r = await ref.read(albumOvernightApiProvider).cancelAlbum(id);
      await refresh(); // tracks already with the bot stay in the list
      return r;
    } catch (_) {
      if (before != null) state = AsyncData(before);
      rethrow;
    }
  }

  Future<CancelResult> cancelAll() async {
    final r = await ref.read(albumOvernightApiProvider).cancelAll();
    await refresh();
    return r;
  }
}

// No automatic retries: a failed load shows its message and "Try again" at once.
final albumOvernightProvider =
    AsyncNotifierProvider.autoDispose<AlbumOvernightController, AlbumOvernight>(AlbumOvernightController.new, retry: (_, _) => null);

/// True when this account may download (so Album Overnight is for them).
final albumOvernightAvailableProvider = Provider.autoDispose<bool>((ref) => ref.watch(onlineFetchEnabledProvider).asData?.value == true);
