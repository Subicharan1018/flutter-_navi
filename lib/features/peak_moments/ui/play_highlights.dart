import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../data/peak_store.dart';
import '../logic/reel.dart';

/// Plays only the saved moments of [songs] (in their order), back to back.
/// Says so when none of them has a moment yet. With [includeSuggested], songs
/// without one contribute their most-replayed stretch, if they have one.
Future<void> playHighlights(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  required String name,
  bool includeSuggested = false,
}) async {
  final plan = buildReel(
    songs,
    ref.read(peakMarksProvider),
    seekLog: ref.read(seekLogProvider),
    includeSuggested: includeSuggested,
  );
  if (plan.isEmpty) {
    showToast(context, 'No saved moments in “$name” yet. Tap the flame while a song plays to save one.');
    return;
  }
  await ref.read(playerProvider.notifier).playReel(plan, name: '$name · Highlights');
}
