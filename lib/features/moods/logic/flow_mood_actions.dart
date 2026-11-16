import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../flow/logic/flow_controller.dart';
import '../../listen/logic/listen_providers.dart';
import 'mood_overrides_provider.dart';

/// Whether you may change songs' moods for everyone (the server's admins).
/// False when signed out or when the server can't say.
final moodAdminProvider = FutureProvider<bool>((ref) async {
  if (!watchSignedIn(ref)) return false;
  try {
    return await ref.read(listenApiProvider).moodsIsAdmin();
  } catch (_) {
    return false;
  }
});

/// Song moods an admin changed on this device since the catalog was last
/// fetched: shown at once, until the next catalog refresh carries them.
class SongMoodEdits extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() => const {};

  void set(String songId, List<String> moods) => state = {...state, songId: List.unmodifiable(moods)};
}

final songMoodEditsProvider = NotifierProvider<SongMoodEdits, Map<String, List<String>>>(SongMoodEdits.new);

/// Queue indices after [current] holding a song [affected] says must go,
/// highest first (so removing them in order keeps the rest valid).
List<int> upcomingToDrop(List<Song> queue, int current, bool Function(Song) affected) =>
    [for (var i = queue.length - 1; i > current; i--) if (affected(queue[i])) i];

/// What Flow's mood buttons do: "Not this mood" and "Change mood…". Tests
/// replace it.
final flowMoodActionsProvider = Provider<FlowMoodActions>(FlowMoodActions.new);

class FlowMoodActions {
  final Ref ref;
  FlowMoodActions(this.ref);

  /// "Not [mood]" on [song]: records it for you on the server (beats the
  /// song's label in Flow and Smart Playlists), drops it and every song still
  /// to come that you marked not [mood], and skips to the next song if it is
  /// the one playing. Returns whether the server saved the mark (it is taken
  /// back if not).
  Future<bool> notThisMood(Song song, String mood) async {
    final saved = ref.read(moodOverridesProvider.notifier).markNot(song.id, mood); // shows at once
    await _leaveFlow(song.id, mood);
    return saved;
  }

  /// "Change mood…": an admin sets [moods] as the song's moods for everyone;
  /// anyone else marks the song's [labels] they left out as not theirs (and
  /// takes back marks on moods they picked again). While Flow plays a mood the
  /// song no longer has, it leaves the queue like "Not this mood".
  Future<bool> setMoods(Song song, {required List<String> moods, required List<String> labels, required bool admin}) async {
    var ok = true;
    if (admin) {
      try {
        final kept = await ref.read(listenApiProvider).setSongMoods(song.id, moods);
        ref.read(songMoodEditsProvider.notifier).set(song.id, kept);
      } catch (_) {
        ok = false;
      }
    } else {
      final marks = ref.read(moodOverridesProvider.notifier);
      final had = ref.read(moodOverridesProvider)[song.id] ?? const <String>{};
      for (final m in labels) {
        if (!moods.contains(m) && !had.contains(m)) ok = await marks.markNot(song.id, m) && ok;
      }
      for (final m in had) {
        if (moods.contains(m)) ok = await marks.unmark(song.id, m) && ok;
      }
    }
    final flow = ref.read(flowProvider);
    final mood = flow.active ? flow.mood : null;
    if (ok && mood != null && !moods.contains(mood)) await _leaveFlow(song.id, mood);
    return ok;
  }

  Future<void> _leaveFlow(String songId, String mood) async {
    final flow = ref.read(flowProvider);
    if (!flow.active || flow.mood != mood) return;
    final player = ref.read(playerProvider.notifier);
    final s = ref.read(playerProvider);
    final marks = ref.read(moodOverridesProvider);
    final edits = ref.read(songMoodEditsProvider);
    bool affected(Song q) =>
        q.id == songId || (marks[q.id]?.contains(mood) ?? false) || (edits[q.id] != null && !edits[q.id]!.contains(mood));
    for (final i in upcomingToDrop(s.queue, s.currentIndex, affected)) {
      await player.removeFromQueue(i);
    }
    if (ref.read(playerProvider).currentSong?.id == songId) await player.playNext();
  }
}
