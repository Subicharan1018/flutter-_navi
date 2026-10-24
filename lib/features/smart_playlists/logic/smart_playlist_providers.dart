import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../models/playlist.dart';
import '../../../models/song.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../data/playlist_folders.dart';
import '../data/smart_evaluator.dart';
import '../data/smart_rules.dart';

const _smartKey = 'smart_playlists';
const _foldersKey = 'playlist_folders';

/// Bookkeeping only: a failed write must not break the tap that caused it.
void _persist(String key, Object value) => HiveBoxes.prefs.put(key, value).ignore();

/// Smart-playlist definitions, kept on the device (never uploaded).
class SmartPlaylistsNotifier extends Notifier<List<SmartPlaylist>> {
  @override
  List<SmartPlaylist> build() {
    final raw = HiveBoxes.prefs.get(_smartKey);
    if (raw is! List) return const [];
    return [for (final r in raw) ?SmartPlaylist.fromJson(r)];
  }

  SmartPlaylist? byId(String id) => state.where((p) => p.id == id).firstOrNull;

  /// A fresh id; ids are never reused, so a deleted playlist's folder
  /// membership can't leak onto a new one.
  String newId() {
    var n = DateTime.now().microsecondsSinceEpoch;
    while (state.any((p) => p.id == '${SmartPlaylist.idPrefix}$n')) {
      n++;
    }
    return '${SmartPlaylist.idPrefix}$n';
  }

  void upsert(SmartPlaylist playlist) {
    final exists = state.any((p) => p.id == playlist.id);
    _save(exists ? [for (final p in state) p.id == playlist.id ? playlist : p] : [...state, playlist]);
  }

  void remove(String id) {
    _save([for (final p in state) if (p.id != id) p]);
    ref.read(playlistFoldersProvider.notifier).move(id, null);
  }

  void _save(List<SmartPlaylist> next) {
    state = next;
    _persist(_smartKey, [for (final p in next) p.toJson()]);
  }
}

final smartPlaylistsProvider =
    NotifierProvider<SmartPlaylistsNotifier, List<SmartPlaylist>>(SmartPlaylistsNotifier.new);

/// The folders and which playlists they hold.
class PlaylistFoldersNotifier extends Notifier<PlaylistFolders> {
  @override
  PlaylistFolders build() => PlaylistFolders.fromJson(HiveBoxes.prefs.get(_foldersKey));

  String create(String name) {
    final id = 'folder:${DateTime.now().microsecondsSinceEpoch}';
    _apply(state.create(id, name));
    return id;
  }

  void rename(String id, String name) => _apply(state.rename(id, name));
  void setPinned(String id, bool pinned) => _apply(state.setPinned(id, pinned));
  void setExpanded(String id, bool expanded) => _apply(state.setExpanded(id, expanded));
  void delete(String id) => _apply(state.delete(id));
  void move(String playlistId, String? folderId) => _apply(state.move(playlistId, folderId));

  void _apply(PlaylistFolders next) {
    if (identical(next, state)) return;
    state = next;
    _persist(_foldersKey, next.toJson());
  }
}

final playlistFoldersProvider =
    NotifierProvider<PlaylistFoldersNotifier, PlaylistFolders>(PlaylistFoldersNotifier.new);

/// Plays the app has recorded: finished ones only, for the last 400 days.
const _playHistoryDays = 400;

/// Per-song facts for rule evaluation: the Drift mirror, the shuffle server's
/// catalog (language, mood) and the local play log. Rebuilt each time a
/// smart playlist is opened, so new plays count.
final smartFactsProvider = FutureProvider.autoDispose<List<SongFacts>>((ref) async {
  final songs = await ref.watch(allSongsProvider.future);
  final catalog = ref.watch(catalogProvider).asData?.value.songs ?? const {};
  final db = ref.read(appDatabaseProvider);
  final since = DateTime.now().subtract(const Duration(days: _playHistoryDays)).millisecondsSinceEpoch;
  final rows = await (db.selectOnly(db.playEvents)
        ..addColumns([db.playEvents.songId, db.playEvents.tsStart])
        ..where(db.playEvents.skipBefore50.equals(false) & db.playEvents.tsStart.isBiggerOrEqualValue(since)))
      .map((r) => (r.read(db.playEvents.songId)!, r.read(db.playEvents.tsStart)!))
      .get();
  final plays = <String, List<int>>{};
  for (final (id, ts) in rows) {
    (plays[id] ??= []).add(ts);
  }
  return [
    for (final s in songs)
      SongFacts(
        song: s,
        languages: catalog[s.id]?.languages ?? const [],
        mood: moodFromCatalog(catalog[s.id]),
        playTimes: plays[s.id] ?? const [],
      ),
  ];
});

/// The songs a smart playlist matches right now, by playlist id.
final smartSongsProvider = Provider.autoDispose.family<AsyncValue<List<Song>>, String>((ref, id) {
  final playlist = ref.watch(smartPlaylistsProvider.select((l) => l.where((p) => p.id == id).firstOrNull));
  if (playlist == null) return const AsyncData([]);
  return ref.watch(smartFactsProvider).whenData(
        (facts) => [for (final f in SmartEvaluator.evaluate(playlist, facts, now: DateTime.now())) f.song],
      );
});

/// Evaluates [playlist] once, for actions (play, queue, save) that run
/// outside a widget tree. Holds the autoDispose facts provider open while it
/// awaits, so it isn't torn down mid-load.
Future<List<Song>> smartSongsOnce(ProviderContainer container, SmartPlaylist playlist) async {
  final sub = container.listen(smartFactsProvider, (_, _) {});
  try {
    final facts = await container.read(smartFactsProvider.future);
    return [for (final f in SmartEvaluator.evaluate(playlist, facts, now: DateTime.now())) f.song];
  } finally {
    sub.close();
  }
}

/// Writes [songs] to Navidrome as an ordinary playlist and remembers it on
/// [smart]. A playlist saved before is overwritten while it still exists on
/// the server; otherwise a new one is made. Throws when the server refuses.
class SmartPlaylistSaver {
  final Ref ref;
  SmartPlaylistSaver(this.ref);

  Future<Playlist> save(SmartPlaylist smart, List<Song> songs) async {
    final svc = ref.read(subsonicServiceProvider);
    final existing = smart.savedPlaylistId == null
        ? null
        : (await svc.getPlaylists()).where((p) => p.id == smart.savedPlaylistId).firstOrNull;
    final target = existing ?? await ref.read(playlistControllerProvider).create(smart.name);
    await svc.setPlaylistSongs(target.id, [for (final s in songs) s.id]);
    ref.read(smartPlaylistsProvider.notifier).upsert(smart.copyWith(savedPlaylistId: target.id));
    ref.invalidate(playlistsProvider);
    return target;
  }
}

final smartPlaylistSaverProvider = Provider((ref) => SmartPlaylistSaver(ref));
