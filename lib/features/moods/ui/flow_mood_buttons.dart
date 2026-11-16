import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast, showToastWithAction;
import '../../../widgets/ui/media.dart' show TintedButton;
import '../../flow/logic/flow_controller.dart';
import '../data/mood_labels.dart';
import '../logic/flow_mood_actions.dart';
import 'mood_picker.dart';

/// The song playing in a mood Flow and that mood, or null when Flow isn't
/// playing a mood.
(Song, String)? flowMoodNow(WidgetRef ref) {
  final mood = ref.watch(flowProvider.select((s) => s.active ? s.mood : null));
  if (mood == null) return null;
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  return song == null ? null : (song, mood);
}

/// "Not this mood" on the song Flow is playing: records it, skips to the next
/// song, and offers "Change mood…". [page] is a context that outlives the tap.
Future<void> runNotThisMood(BuildContext page, Song song, String mood) async {
  final c = ProviderScope.containerOf(page);
  final ok = await c.read(flowMoodActionsProvider).notThisMood(song, mood);
  if (!page.mounted) return;
  if (!ok) {
    showToast(page, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  showToastWithAction(
    page,
    '“${song.title}” won’t play as ${moodTitle(mood)} for you',
    actionLabel: 'Change Mood…',
    onAction: () => showSongMoodPicker(page, song),
  );
}

/// Home's Flow surface: while a mood Flow plays, "Not Sad" (and so on) and
/// "Change Mood…" for the song playing. Nothing otherwise.
class FlowMoodButtons extends ConsumerWidget {
  const FlowMoodButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = flowMoodNow(ref);
    if (now == null) return const SizedBox.shrink();
    final (song, mood) = now;
    final t = ThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.md),
        Text('Playing “${song.title}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            TintedButton(
              key: const ValueKey('flow-not-this-mood'),
              label: 'Not ${moodTitle(mood)}',
              glyph: NaviGlyph.thumbDown,
              onTap: () => runNotThisMood(context, song, mood),
            ),
            TintedButton(
              key: const ValueKey('flow-change-mood'),
              label: 'Change Mood…',
              glyph: NaviGlyph.sliders,
              onTap: () => showSongMoodPicker(context, song),
            ),
          ],
        ),
      ],
    );
  }
}
