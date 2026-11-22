import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../data/rotation_models.dart';
import '../logic/rotation_providers.dart';

/// Taste > Rotation: songs resting (yours and the ones the server rested),
/// seasonal songs with whether their season is on, and the switches for all
/// of it. Draws nothing until the server has answered.
class RotationTasteSection extends ConsumerWidget {
  const RotationTasteSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rotationProvider).asData?.value;
    if (r == null) return const SizedBox.shrink();
    final notifier = ref.read(rotationProvider.notifier);
    Future<void> run(Future<void> Function() call, String done) async {
      try {
        await call();
        if (context.mounted) showToast(context, done);
      } catch (_) {
        if (context.mounted) showToast(context, 'Couldn’t save that. Check your connection and try again.');
      }
    }

    return Column(children: [
      if (r.resting.isNotEmpty)
        GroupedSection(
          header: 'Resting',
          footer: 'Left out of Discover, your weekly mix, Flow and Smart Shuffle until the date shown.',
          children: [
            for (final s in r.resting)
              GroupedRow(
                title: s.title,
                subtitle: [if (s.artist.isNotEmpty) s.artist, backOnLabel(s.until), if (s.auto) 'rested for you'].join(' · '),
                showChevron: false,
                trailing: _TextAction(
                  label: 'Bring back',
                  semantics: 'Bring back ${s.title}',
                  onTap: () => run(() => notifier.unrest(s.songId), '${s.title} is back in your mixes'),
                ),
              ),
          ],
        ),
      if (r.seasonal.isNotEmpty)
        GroupedSection(
          header: 'Seasonal',
          footer: 'Out of your mixes until their season. The server guesses from the title and from when you play them; “Not seasonal” stops that.',
          children: [
            for (final s in r.seasonal)
              GroupedRow(
                title: s.title,
                subtitle: [if (s.artist.isNotEmpty) s.artist, s.inSeason ? '${s.label}: in season' : s.label].join(' · '),
                showChevron: false,
                trailing: _TextAction(
                  label: 'Not seasonal',
                  semantics: '${s.title} is not seasonal',
                  onTap: () => run(() => notifier.setSeason(s.songId, 'none'), '${s.title} plays all year'),
                ),
              ),
          ],
        ),
      GroupedSection(
        header: 'Rotation',
        children: [
          GroupedSwitchRow(
            title: 'Rest songs I wear out',
            subtitle: 'Many plays in two weeks, then skipped: a 2 week rest',
            value: r.prefs.autoRest,
            onChanged: (v) => run(() => notifier.savePrefs(autoRest: v), v ? 'Worn-out songs will rest' : 'Songs won’t rest by themselves'),
          ),
          GroupedSwitchRow(
            title: 'Seasonal songs only in season',
            subtitle: 'Deepavali, Pongal, Christmas and more',
            value: r.prefs.seasons,
            onChanged: (v) => run(() => notifier.savePrefs(seasons: v), v ? 'Seasonal songs stay in season' : 'Seasonal songs play all year'),
          ),
          GroupedSwitchRow(
            title: 'Back in rotation',
            subtitle: 'Old favourites on Home and in Smart Shuffle',
            value: r.prefs.back,
            onChanged: (v) => run(() => notifier.savePrefs(back: v), v ? 'Old favourites are back' : 'Old favourites are off'),
          ),
        ],
      ),
    ]);
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final String semantics;
  final VoidCallback onTap;
  const _TextAction({required this.label, required this.semantics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(height: 44, child: Center(child: Text(label, style: t.body.copyWith(color: t.accent)))),
      ),
    );
  }
}
