import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/remote_queue_provider.dart';
import '../widgets/ui/action_sheet.dart' show showToast;

// ── Queue edits the person makes ─────────────────────────────────────────────
//
// Each goes to the queue that is playing: this device's own, or, while another
// of your devices plays (this one is its remote), that device's queue through
// the session link. Code that drives the player by itself (Jam, Flow, Smart
// Shuffle) keeps calling playerProvider directly: it is about this device.

/// True while another of this account's devices plays and this one controls it.
bool isRemoteQueue(WidgetRef ref) => ref.read(playerProvider).syncMode == SyncMode.passive;

/// Play next ([next]) or add to the end of the queue, without a toast.
Future<void> addToUpNext(WidgetRef ref, List<Song> songs, {required bool next}) async {
  if (songs.isEmpty) return;
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).insert(songs, next ? QueueSpot.next : QueueSpot.end);
    return;
  }
  final notifier = ref.read(playerProvider.notifier);
  if (next) {
    // Insert in reverse so the first song ends up immediately next.
    for (final s in songs.reversed) {
      await notifier.insertNext(s);
    }
  } else {
    await notifier.addAllToQueue(songs);
  }
}

/// [songs] dropped into the queue at absolute index [at].
Future<void> queueInsertAt(WidgetRef ref, List<Song> songs, int at) async {
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).insert(songs, QueueSpot.at(at));
  } else {
    await ref.read(playerProvider.notifier).insertAllNext(songs, atIndex: at);
  }
}

Future<void> queueRemoveAt(WidgetRef ref, int index) async {
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).remove(index);
  } else {
    await ref.read(playerProvider.notifier).removeFromQueue(index);
  }
}

Future<void> queueMove(WidgetRef ref, int from, int to) async {
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).move(from, to);
  } else {
    await ref.read(playerProvider.notifier).reorderQueue(from, to);
  }
}

/// Removes every song after the one playing.
Future<void> queueClearUpcoming(WidgetRef ref) async {
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).clearUpcoming();
  } else {
    await ref.read(playerProvider.notifier).clearUpcoming();
  }
}

/// Plays the queue's song at [index] (on the device that plays).
Future<void> queueJumpTo(WidgetRef ref, int index) async {
  if (isRemoteQueue(ref)) {
    ref.read(remoteQueueProvider.notifier).jumpTo(index);
  } else {
    await ref.read(playerProvider.notifier).jumpTo(index);
  }
}

/// Queue [songs] to play next (after the current song) or last (end of the
/// queue). With nothing playing, starts playback instead — there is no queue
/// to add to. Confirms with a toast.
Future<void> queueSongs(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  required bool next,
  String? label,
}) async {
  if (songs.isEmpty) return;
  final notifier = ref.read(playerProvider.notifier);
  if (isRemoteQueue(ref)) {
    // Another device plays: its queue gets the songs (it always has one).
    if (!ref.read(remoteQueueProvider.notifier).insert(songs, next ? QueueSpot.next : QueueSpot.end)) return;
  } else if (ref.read(playerProvider).queue.isEmpty) {
    await notifier.setQueue(songs, 0, playlistName: label, unshuffledSongs: songs);
  } else {
    await addToUpNext(ref, songs, next: next);
  }
  if (!context.mounted) return;
  final what = label ?? (songs.length == 1 ? songs.first.title : '${songs.length} songs');
  showToast(context, next ? 'Playing next: $what' : 'Playing last: $what');
}

/// Plays a whole collection (album, playlist, artist) from its first song:
/// loads the songs, starts them as the queue named [name].
Future<void> playCollection(
  BuildContext context,
  WidgetRef ref,
  Future<List<Song>> Function() load,
  String name,
) async {
  try {
    final songs = await load();
    if (songs.isEmpty) return;
    await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: name, unshuffledSongs: songs);
  } catch (_) {
    if (context.mounted) showToast(context, 'Couldn’t start “$name”. Check your connection and try again.');
  }
}
