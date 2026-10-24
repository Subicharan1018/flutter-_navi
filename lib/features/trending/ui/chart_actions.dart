import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../data/trending_models.dart';
import '../logic/trending_providers.dart';

/// A chart song was tapped: play the chart from it, in rank order, or say
/// why it can't play.
Future<void> playFromChart(BuildContext context, WidgetRef ref, TrendingChart chart, ChartEntry entry) async {
  if (!entry.playable) {
    showToast(context, '${entry.title}: ${entry.unavailableLine}');
    return;
  }
  await _play(context, ref, chart, from: entry);
}

/// Play (or shuffle) the whole chart.
Future<void> playChart(BuildContext context, WidgetRef ref, TrendingChart chart, {bool shuffle = false}) =>
    _play(context, ref, chart, shuffle: shuffle);

Future<void> _play(BuildContext context, WidgetRef ref, TrendingChart chart,
    {ChartEntry? from, bool shuffle = false}) async {
  var ok = false;
  try {
    ok = await ref.read(chartPlayerProvider).play(chart, from: from, shuffle: shuffle);
  } catch (_) {}
  if (!ok && context.mounted) {
    showToast(context, 'Couldn’t load the chart’s songs. Check your connection and try again.');
  }
}

/// "Updated today" / "Updated yesterday" / "Updated 12 Oct".
String chartDateLine(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final days = day(now ?? DateTime.now()).difference(day(date)).inDays;
  if (days <= 0) return 'Updated today';
  if (days == 1) return 'Updated yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Updated ${date.day} ${months[date.month - 1]}';
}
