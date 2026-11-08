import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';

/// Where "seen" flags live. Hive in the app, a memory store in tests.
abstract class HintStore {
  bool seen(String key);
  void markSeen(String key);
}

class HiveHintStore implements HintStore {
  @override
  bool seen(String key) {
    try {
      return HiveBoxes.prefs.get('hint_$key') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void markSeen(String key) {
    try {
      HiveBoxes.prefs.put('hint_$key', true);
    } catch (_) {}
  }
}

final hintStoreProvider = Provider<HintStore>((ref) => HiveHintStore());

/// The first-run line above a room's queue ("Press and hold a song to reorder
/// or remove it"). It shows until the person dismisses it or uses what it
/// teaches (a reorder, a removal), and never again after that.
class JamQueueHint extends Notifier<bool> {
  static const key = 'jam_queue_reorder';

  @override
  bool build() => !ref.read(hintStoreProvider).seen(key);

  /// Dismissed, or the person did what it describes.
  void done() {
    if (!state) return;
    ref.read(hintStoreProvider).markSeen(key);
    state = false;
  }
}

final jamQueueHintProvider = NotifierProvider<JamQueueHint, bool>(JamQueueHint.new);
