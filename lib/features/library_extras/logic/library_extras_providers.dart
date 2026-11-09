import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/playlist_access.dart';
import '../data/duplicates.dart';
import '../data/shared_inbox.dart';

Set<String> _readSet(String key) {
  try {
    final raw = HiveBoxes.prefs.get(key);
    return raw is List ? {for (final e in raw) e.toString()} : <String>{};
  } catch (_) {
    return <String>{}; // prefs not open (tests, early start): nothing remembered
  }
}

bool _hasKey(String key) {
  try {
    return HiveBoxes.prefs.containsKey(key);
  } catch (_) {
    return false;
  }
}

void _writeSet(String key, Set<String> v) {
  // Bookkeeping only: a failed write must not break the tap that caused it.
  try {
    HiveBoxes.prefs.put(key, v.toList()).ignore();
  } catch (_) {}
}

/// Songs the user chose to hide as duplicates. Device-local; the files and the
/// server are never touched.
class HiddenSongsNotifier extends Notifier<Set<String>> {
  static const _key = 'library_hidden_duplicate_songs';

  @override
  Set<String> build() => _readSet(_key);

  void hide(Iterable<String> ids) {
    state = {...state, ...ids};
    _writeSet(_key, state);
  }

  void restore(Iterable<String> ids) {
    state = {...state}..removeAll(ids);
    _writeSet(_key, state);
  }
}

final hiddenSongsProvider = NotifierProvider<HiddenSongsNotifier, Set<String>>(HiddenSongsNotifier.new);

/// All duplicate groups found in the synced library.
class DuplicateScan {
  final List<DupGroup> songs;
  final List<DupGroup> albums;
  final List<DupGroup> artists;
  const DuplicateScan(this.songs, this.albums, this.artists);
  int get total => songs.length + albums.length + artists.length;
}

final duplicateScanProvider = FutureProvider.autoDispose<DuplicateScan>((ref) async {
  final all = await ref.watch(allSongsProvider.future);
  return DuplicateScan(findDuplicateSongs(all), findDuplicateAlbums(all), findDuplicateArtists(all));
});

/// How many duplicate groups there are; 0 while scanning or if the library
/// can't be read, so the Library only offers the tool when there is something.
final duplicateCountProvider = Provider.autoDispose<int>((ref) {
  // Only once the library is already loaded elsewhere: the Library page never
  // starts a sync or opens the database just to decide whether to show a link.
  ref.watch(librarySyncProvider.select((s) => s.revision));
  if (!ref.exists(allSongsProvider)) return 0;
  return ref.watch(duplicateScanProvider).maybeWhen(data: (s) => s.total, orElse: () => 0);
});

/// Per-user "Shared with you" inbox state: which shared playlists were seen,
/// which were dismissed.
class SharedInboxState {
  final Set<String> seen;
  final Set<String> dismissed;

  /// False until this user's first look at the list: what is already shared then
  /// is the starting point, not "new".
  final bool baselined;
  const SharedInboxState(this.seen, this.dismissed, {this.baselined = true});
}

class SharedInboxNotifier extends Notifier<SharedInboxState> {
  String get _user => ref.read(settingsProvider).username;

  @override
  SharedInboxState build() {
    final user = ref.watch(settingsProvider.select((s) => s.username));
    return SharedInboxState(
      _readSet(inboxPrefsKey('seen', user)),
      _readSet(inboxPrefsKey('dismissed', user)),
      baselined: _hasKey(inboxPrefsKey('seen', user)),
    );
  }

  /// First sight of the list: everything already there counts as seen.
  void baseline(Iterable<String> ids) {
    if (state.baselined) return;
    final next = {...state.seen, ...ids};
    state = SharedInboxState(next, state.dismissed);
    _writeSet(inboxPrefsKey('seen', _user), next);
  }

  void markSeen(Iterable<String> ids) {
    final next = {...state.seen, ...ids};
    if (next.length == state.seen.length) return;
    state = SharedInboxState(next, state.dismissed);
    _writeSet(inboxPrefsKey('seen', _user), next);
  }

  void dismiss(String id) {
    final d = {...state.dismissed, id};
    state = SharedInboxState({...state.seen, id}, d);
    _writeSet(inboxPrefsKey('dismissed', _user), d);
  }
}

final sharedInboxStateProvider = NotifierProvider<SharedInboxNotifier, SharedInboxState>(SharedInboxNotifier.new);

/// The inbox as the Library shows it (badge count + list).
final sharedInboxProvider = Provider.autoDispose<SharedInbox>((ref) {
  final me = ref.watch(settingsProvider.select((s) => s.username));
  final all = ref.watch(playlistsProvider).asData?.value ?? const [];
  final st = ref.watch(sharedInboxStateProvider);
  final shared = [for (final p in all) if (p.isSharedFor(me)) p.id];
  if (!st.baselined) {
    if (ref.watch(playlistsProvider).hasValue) {
      Future.microtask(() => ref.mounted ? ref.read(sharedInboxStateProvider.notifier).baseline(shared) : null);
    }
    return buildSharedInbox(all, me, seen: shared.toSet(), dismissed: st.dismissed);
  }
  return buildSharedInbox(all, me, seen: st.seen, dismissed: st.dismissed);
});
