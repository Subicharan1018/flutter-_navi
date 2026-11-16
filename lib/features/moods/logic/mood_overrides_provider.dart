import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../listen/logic/listen_providers.dart';

/// Your "Not this mood" marks (song id → moods you said it is not), kept on the
/// shuffle server so they apply on every device and in Flow. Loaded once per
/// account; a mark shows at once and is taken back if the server refuses it.
/// Kept alive: Smart Playlists and the song menu read it at any time.
class MoodOverridesNotifier extends Notifier<Map<String, Set<String>>> {
  @override
  Map<String, Set<String>> build() {
    if (watchSignedIn(ref)) Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    try {
      final got = await ref.read(listenApiProvider).moodOverrides();
      if (!ref.mounted) return;
      // Marks made while this loaded stay.
      state = {
        for (final id in {...got.keys, ...state.keys}) id: {...?got[id], ...?state[id]},
      };
    } catch (_) {
      // No marks: the server's labels apply as they are.
    }
  }

  /// Marks [songId] as not [mood]. Returns false (and takes the mark back) when
  /// the server couldn't save it.
  Future<bool> markNot(String songId, String mood) => _set(songId, mood, add: true);

  /// Takes a mark back (Undo). Returns false when the server couldn't.
  Future<bool> unmark(String songId, String mood) => _set(songId, mood, add: false);

  Future<bool> _set(String songId, String mood, {required bool add}) async {
    final before = state;
    _apply(songId, mood, add: add);
    try {
      await ref.read(listenApiProvider).setNotThisMood(songId, mood, undo: !add);
      return true;
    } catch (_) {
      if (ref.mounted) state = before;
      return false;
    }
  }

  void _apply(String songId, String mood, {required bool add}) {
    final next = {...?state[songId]};
    add ? next.add(mood) : next.remove(mood);
    state = {
      for (final e in state.entries)
        if (e.key != songId) e.key: e.value,
      if (next.isNotEmpty) songId: next,
    };
  }
}

final moodOverridesProvider =
    NotifierProvider<MoodOverridesNotifier, Map<String, Set<String>>>(MoodOverridesNotifier.new);
