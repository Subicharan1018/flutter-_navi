import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup, showToast;
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

/// Long press on a chart row: Play next / Play last for that song. A song that
/// isn't in the library says so instead.
Future<void> showChartEntryMenu(BuildContext context, WidgetRef ref, ChartEntry entry) async {
  if (!entry.playable) {
    showToast(context, '${entry.title}: ${entry.unavailableLine}');
    return;
  }
  await showPlatformSheet<void>(
    context: context,
    title: entry.title,
    builder: (sheet) {
      Future<void> queue(bool next) async {
        Song? song;
        try {
          song = await ref.read(chartPlayerProvider).songFor(entry);
        } catch (_) {}
        if (!context.mounted) return;
        if (song == null) {
          showToast(context, '${entry.title}: Couldn’t load this song. Check your connection and try again.');
          return;
        }
        await queueSongs(context, ref, [song], next: next);
      }

      NaviIcon glyph() => NaviIcon(NaviGlyph.queue, size: 20, color: ThemeTokens.of(sheet).textSecondary);
      return SheetGroup(children: [
        SheetAction(label: 'Play Next', trailing: glyph(), onTap: () => queue(true)),
        SheetAction(label: 'Play Last', trailing: glyph(), onTap: () => queue(false)),
      ]);
    },
  );
}

/// Play (or shuffle) the whole chart.
Future<void> playChart(BuildContext context, WidgetRef ref, TrendingChart chart, {bool shuffle = false}) =>
    _play(context, ref, chart, shuffle: shuffle);

Future<void> _play(BuildContext context, WidgetRef ref, TrendingChart chart,
    {ChartEntry? from, bool shuffle = false}) async {
  var result = ChartPlayResult.noSongs;
  try {
    result = await ref.read(chartPlayerProvider).play(chart, from: from, shuffle: shuffle);
  } catch (_) {}
  if (!context.mounted) return;
  switch (result) {
    case ChartPlayResult.played:
      break;
    case ChartPlayResult.entryMissing:
      showToast(context, '${from?.title ?? 'This song'}: Not in your library');
    case ChartPlayResult.noSongs:
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
