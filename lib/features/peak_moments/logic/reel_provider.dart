import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reel.dart';

/// The highlight reel playing right now, or null for normal playback. Set and
/// cleared by the player (`PlayerNotifier.playReel`); the UI only reads it.
class ReelNotifier extends Notifier<ReelPlan?> {
  @override
  ReelPlan? build() => null;

  void set(ReelPlan plan) => state = plan;
  void clear() => state = null;
}

final reelProvider = NotifierProvider<ReelNotifier, ReelPlan?>(ReelNotifier.new);
