import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/format.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/art/navi_icons.dart';
import '../../widgets/ui/action_sheet.dart';
import 'play_stats.dart' show relativeDay;
import 'recent_queues.dart';
import 'recent_queues_providers.dart';
import 'save_as_playlist.dart';

/// "Save queue" and "Recent queues" for the queue pane (R6).

/// The queue as a playlist: asks for a name, defaults to today's date.
Future<void> saveQueueAsPlaylist(BuildContext context, WidgetRef ref, List<Song> queue, {String? source}) {
  final now = DateTime.now();
  final base = source != null && source.trim().isNotEmpty ? source.trim() : 'Queue';
  return savePlaylistFromSongs(
    context,
    ref,
    songs: queue,
    suggestedName: '$base ${now.day}/${now.month}',
    title: 'Save Queue as Playlist',
  );
}

/// Plays a remembered queue from the song that was playing.
Future<void> restoreRecentQueue(WidgetRef ref, RecentQueue q) {
  return ref.read(playerProvider.notifier).setQueue(q.songs, q.index, playlistName: q.source, unshuffledSongs: q.songs);
}

/// "Yesterday · 24 songs".
String recentQueueDetail(RecentQueue q, DateTime now) =>
    '${relativeDay(q.savedAt, now)} · ${songCount(q.songs.length)}';

Future<void> showRecentQueues(BuildContext context) =>
    showPlatformSheet(context: context, title: 'Recent Queues', builder: (_) => const _RecentQueuesSheet());

class _RecentQueuesSheet extends ConsumerWidget {
  const _RecentQueuesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recentQueuesProvider);
    final now = DateTime.now();
    final page = Navigator.of(context).context;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Queues you move on from are kept here, so you can bring one back.', textAlign: TextAlign.center),
      );
    }
    return SingleChildScrollView(
      child: SheetGroup(children: [
        for (final q in list)
          SheetAction(
            key: ValueKey(q.savedAt.millisecondsSinceEpoch),
            label: RecentQueues.title(q),
            detail: recentQueueDetail(q, now),
            icon: NaviGlyph.queue,
            onTap: () async {
              await restoreRecentQueue(ref, q);
              if (page.mounted) showToast(page, 'Queue restored');
            },
          ),
      ]),
    );
  }
}
