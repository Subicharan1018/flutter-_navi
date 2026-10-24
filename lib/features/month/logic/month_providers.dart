import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';

/// The month picked on the page (null: this month).
class SelectedMonth extends Notifier<MonthKey?> {
  @override
  MonthKey? build() => null;

  void select(MonthKey? m) => state = m;
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, MonthKey?>(SelectedMonth.new);

/// A month of listening. Re-asks when the account changes.
final monthStatsProvider = FutureProvider.autoDispose.family<MonthStats?, MonthKey?>(
  (ref, month) async {
    if (!watchSignedIn(ref)) return null;
    return ref.read(listenApiProvider).month(month);
  },
  retry: (_, _) => null,
);

/// "+2h 10m" / "−45m" against the month before; null when there is nothing to compare.
String? minutesChange(int now, int before) {
  if (before <= 0) return null;
  final d = now - before;
  if (d == 0) return 'Same as last month';
  final m = d.abs();
  final text = m >= 60 ? '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}' : '${m}m';
  return '${d > 0 ? '+' : '−'}$text on last month';
}

/// "3h 20m", "45m".
String minutesLabel(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}m'}' : '${minutes}m';
