import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import '../widgets/ui/action_sheet.dart' show showToast;

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
  if (ref.read(playerProvider).queue.isEmpty) {
    await notifier.setQueue(songs, 0, playlistName: label, unshuffledSongs: songs);
  } else if (next) {
    // Insert in reverse so the first song ends up immediately next.
    for (final s in songs.reversed) {
      await notifier.insertNext(s);
    }
  } else {
    await notifier.addAllToQueue(songs);
  }
  if (!context.mounted) return;
  final what = label ?? (songs.length == 1 ? songs.first.title : '${songs.length} songs');
  showToast(context, next ? 'Playing next: $what' : 'Playing last: $what');
}
