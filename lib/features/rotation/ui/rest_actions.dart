import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup, showToast, showToastWithAction;
import '../data/rotation_models.dart';
import '../logic/rotation_providers.dart';

/// Season keys the server knows, in the order the sheet lists them. The
/// labels come from the server when it has answered; these are the fallback.
const _seasonLabels = {
  'deepavali': 'Deepavali',
  'pongal': 'Pongal',
  'christmas': 'Christmas',
  'navaratri': 'Navaratri',
  'ayyappa': 'Ayyappa season',
  'vinayagar': 'Vinayagar Chaturthi',
};

/// "Rest This Song…" and "Seasonal…" for a song's menu, as one group. [page]
/// is the page under the sheet: the actions run there after the sheet closes.
class RotationActions extends ConsumerWidget {
  final Song song;
  final BuildContext page;
  const RotationActions({super.key, required this.song, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rotation = ref.watch(rotationProvider).asData?.value;
    final resting = rotation?.isResting(song.id) ?? false;
    final season = rotation?.seasonOf(song.id);
    final container = ProviderScope.containerOf(page);
    return SheetGroup(children: [
      SheetAction(
        label: resting ? 'Bring Back' : 'Rest This Song…',
        detail: resting ? 'It is resting from your mixes' : 'Keep it out of your mixes for a while',
        icon: NaviGlyph.clock,
        onTap: resting ? () => bringBack(container, page, song) : () => showRestSheet(page, container, song),
      ),
      SheetAction(
        label: season == null ? 'Seasonal…' : 'Seasonal: ${season.label}',
        detail: 'Only in mixes during its season',
        icon: NaviGlyph.calendar,
        onTap: () => showSeasonSheet(page, container, song, rotation),
      ),
    ]);
  }
}

/// 2 weeks / 1 month / 3 months, then the server leaves the song out of
/// Discover, your weekly mix, Flow and Smart Shuffle until it is back.
Future<void> showRestSheet(BuildContext page, ProviderContainer c, Song song) {
  return showPlatformSheet<void>(
    context: page,
    title: 'Rest this song for',
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: SheetGroup(children: [
        for (final length in RestLength.values)
          SheetAction(label: length.label, onTap: () => restSong(c, page, song, length)),
      ]),
    ),
  );
}

Future<void> restSong(ProviderContainer c, BuildContext page, Song song, RestLength length) async {
  try {
    await c.read(rotationProvider.notifier).rest(song, length);
  } catch (_) {
    if (page.mounted) showToast(page, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  if (!page.mounted) return;
  showToastWithAction(
    page,
    '${song.title} is resting for ${length.label}',
    actionLabel: 'Undo',
    onAction: () => c.read(rotationProvider.notifier).unrest(song.id),
  );
}

Future<void> bringBack(ProviderContainer c, BuildContext page, Song song) async {
  try {
    await c.read(rotationProvider.notifier).unrest(song.id);
  } catch (_) {
    if (page.mounted) showToast(page, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  if (page.mounted) showToast(page, '${song.title} is back in your mixes');
}

/// Pick the season a song belongs to; outside it the song stays out of
/// recommendations and Smart Shuffle. "Not seasonal" stops the server
/// guessing; "Clear" forgets your tag.
Future<void> showSeasonSheet(BuildContext page, ProviderContainer c, Song song, Rotation? rotation) {
  final current = rotation?.seasonOf(song.id);
  final labels = {
    for (final s in rotation?.seasons ?? const <SeasonInfo>[]) s.key: s.label,
  };
  return showPlatformSheet<void>(
    context: page,
    title: 'Seasonal',
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      Widget mark(bool on) => SizedBox(width: 22, child: on ? NaviIcon(NaviGlyph.check, size: 20, color: t.accent) : null);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetGroup(children: [
            for (final key in _seasonLabels.keys)
              SheetAction(
                label: labels[key] ?? _seasonLabels[key]!,
                trailing: mark(current?.season == key),
                onTap: () => tagSeason(c, page, song, key, labels[key] ?? _seasonLabels[key]!),
              ),
          ]),
          SheetGroup(children: [
            SheetAction(label: 'Not seasonal', onTap: () => tagSeason(c, page, song, 'none', null)),
            if (current != null && current.manual)
              SheetAction(label: 'Clear my tag', onTap: () => tagSeason(c, page, song, null, null)),
          ]),
        ]),
      );
    },
  );
}

Future<void> tagSeason(ProviderContainer c, BuildContext page, Song song, String? season, String? label) async {
  try {
    await c.read(rotationProvider.notifier).setSeason(song.id, season);
  } catch (_) {
    if (page.mounted) showToast(page, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  if (!page.mounted) return;
  showToast(
    page,
    season == null
        ? 'Tag cleared'
        : season == 'none'
            ? '${song.title} is not seasonal'
            : '${song.title} plays in $label only',
  );
}
