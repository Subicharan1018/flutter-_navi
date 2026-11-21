import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/ui/horizontal_shelf.dart';
import '../../../widgets/ui/media.dart';
import '../logic/weekly_providers.dart';
import 'weekly_exploration_screen.dart';

/// Home's "Weekly Exploration" shelf: this week's songs you have not decided on, as covers. Tapping opens the
/// page (a preview plays there). Hidden unless the account may download and there is something to hear.
class WeeklyExplorationSection extends ConsumerWidget {
  static const double _cover = 150;
  const WeeklyExplorationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weeklyAvailableProvider)) return const SizedBox.shrink();
    // Only the count and the first covers matter here: the shelf does not rebuild for a download's progress.
    final shown = ref.watch(weeklyExplorationProvider.select((a) {
      final w = a.asData?.value;
      if (w == null || !w.enabled) return const <_Tile>[];
      return [for (final p in w.pending.take(10)) _Tile(p.id, p.title, p.artist, p.coverUrl)];
    }));
    if (shown.isEmpty) return const SizedBox.shrink();
    void open() => navigateInApp(context, const WeeklyExplorationScreen(), title: 'Weekly Exploration');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Weekly Exploration', onTap: open),
        HorizontalShelf(
          height: _cover + captionExtent(context),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final p = shown[i];
            return MediaCard(title: p.title, subtitle: p.artist, artUrl: p.cover, size: _cover, onTap: open);
          },
        ),
      ],
    );
  }
}

/// What a shelf card needs, with equality so a Keep elsewhere only rebuilds the shelf when its songs change.
@immutable
class _Tile {
  final int id;
  final String title;
  final String artist;
  final String? cover;
  const _Tile(this.id, this.title, this.artist, this.cover);

  @override
  bool operator ==(Object o) => o is _Tile && o.id == id && o.title == title && o.artist == artist && o.cover == cover;

  @override
  int get hashCode => Object.hash(id, title, artist, cover);
}
