import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../player/player_controls.dart' show GlassCircleButton;
import '../../../providers/player_provider.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../data/peak_store.dart';

/// "This is the best part": one tap saves a moment at the playhead, a tap
/// inside a saved moment (or a long-press) removes it. Sits beside the star.
class PeakMarkButton extends ConsumerWidget {
  const PeakMarkButton({super.key, required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marked = ref.watch(peakMarksProvider.select((m) => m.of(song.id).isNotEmpty));
    return GlassCircleButton(
      icon: NaviGlyph.flame,
      filled: marked,
      semanticLabel: marked ? 'Saved moments. Tap to save another or remove one' : 'Save this moment as the best part',
      onTap: () => _tap(context, ref),
      onLongPress: () => _remove(context, ref),
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final pos = ref.read(playerProvider.notifier).positionMs;
    final out = await ref.read(peakMarksProvider.notifier).toggleAt(song.id, pos, durationMs: song.duration * 1000);
    if (!context.mounted) return;
    showToast(
      context,
      switch (out) {
        MarkOutcome.added => 'Saved from ${formatTrackDuration(pos ~/ 1000)}. Drag its end on the bar to change the length.',
        MarkOutcome.removed => 'Moment removed',
        MarkOutcome.noRoom => 'No room for a moment here. Try a part of the song that isn’t saved yet.',
      },
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    HapticFeedback.heavyImpact();
    final pos = ref.read(playerProvider.notifier).positionMs;
    final removed = await ref.read(peakMarksProvider.notifier).removeNear(song.id, pos);
    if (!context.mounted) return;
    showToast(context, removed ? 'Moment removed' : 'No saved moments in this song');
  }
}
