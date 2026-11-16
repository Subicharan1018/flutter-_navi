import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../flow/logic/flow_controller.dart';
import '../data/mood_labels.dart';
import '../logic/mood_overrides_provider.dart';

/// "Not Sad" (and so on) in the song menu, for a song in a mood Smart Playlist ([mood])
/// or in the queue while Flow plays a mood chip. Draws nothing elsewhere.
class NotThisMoodAction extends ConsumerWidget {
  final Song song;

  /// The mood of the list the menu was opened from, if any.
  final String? mood;

  /// The page under the sheet: the action runs there after the sheet closes.
  final BuildContext page;

  const NotThisMoodAction({super.key, required this.song, required this.page, this.mood});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowMood = ref.watch(flowProvider.select((s) => s.active ? s.mood : null));
    final inFlow = flowMood != null && ref.watch(playerProvider.select((s) => s.queue.any((q) => q.id == song.id)));
    final target = mood ?? (inFlow ? flowMood : null);
    if (target == null || target.isEmpty) return const SizedBox.shrink();
    final container = ProviderScope.containerOf(page);
    return SheetGroup(children: [
      SheetAction(
        label: 'Not ${moodTitle(target)}',
        icon: NaviGlyph.thumbDown,
        onTap: () => markNotThisMood(container, page, song, target),
      ),
    ]);
  }
}

/// Marks [song] as not [mood] for this listener (kept on the server, so Flow
/// and Smart Playlists on every device follow it), drops it from what Flow
/// still has queued for that mood, and offers Undo.
Future<void> markNotThisMood(ProviderContainer c, BuildContext page, Song song, String mood) async {
  final ok = await c.read(moodOverridesProvider.notifier).markNot(song.id, mood);
  if (!page.mounted) return;
  if (!ok) {
    showToast(page, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  if (c.read(flowProvider).mood == mood) await _dropUpcoming(c, song.id);
  if (!page.mounted) return;
  showToastWithAction(
    page,
    'Won’t count as ${moodTitle(mood)} for you',
    actionLabel: 'Undo',
    onAction: () => c.read(moodOverridesProvider.notifier).unmark(song.id, mood),
  );
}

/// Takes the song out of the queue after the one playing (the playing one stays).
Future<void> _dropUpcoming(ProviderContainer c, String songId) async {
  final player = c.read(playerProvider.notifier);
  final s = c.read(playerProvider);
  for (var i = s.queue.length - 1; i > s.currentIndex; i--) {
    if (s.queue[i].id == songId) await player.removeFromQueue(i);
  }
}
