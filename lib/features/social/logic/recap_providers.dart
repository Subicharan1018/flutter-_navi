import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../data/social_models.dart';
import 'reaction_rules.dart';
import 'social_providers.dart';

/// Which week's Home card the person dismissed (the Monday, see [weekKey]).
abstract class RecapDismissStore {
  String? read();
  void write(String week);
}

class HiveRecapDismissStore implements RecapDismissStore {
  static const _key = 'recap_dismissed_week_v1';

  @override
  String? read() {
    try {
      final v = HiveBoxes.prefs.get(_key);
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String week) {
    try {
      HiveBoxes.prefs.put(_key, week);
    } catch (_) {}
  }
}

final recapDismissStoreProvider = Provider<RecapDismissStore>((ref) => HiveRecapDismissStore());

/// The clock, so tests can pick the week.
final recapClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class RecapDismissed extends Notifier<String?> {
  @override
  String? build() => ref.read(recapDismissStoreProvider).read();

  /// "Not now" on Home hides the card until next week.
  void dismissThisWeek() {
    final week = weekKey(ref.read(recapClockProvider)());
    state = week;
    ref.read(recapDismissStoreProvider).write(week);
  }
}

final recapDismissedProvider = NotifierProvider<RecapDismissed, String?>(RecapDismissed.new);

/// What Home shows: the recap when it has something to say and the person
/// hasn't dismissed this week's card. Null otherwise (card hidden).
final homeRecapProvider = Provider.autoDispose<WeeklyRecap?>((ref) {
  final recap = ref.watch(recapProvider).asData?.value;
  if (recap == null || !recap.hasContent) return null;
  final dismissed = ref.watch(recapDismissedProvider);
  return dismissed == weekKey(ref.read(recapClockProvider)()) ? null : recap;
});
