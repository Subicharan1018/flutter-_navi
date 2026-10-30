import '../../../widgets/ui/horizontal_shelf.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../logic/discover_providers.dart';

/// Home's lead: "New in Your Library" — what the charts just brought in and
/// songs you've never played, as big covers with Play / Shuffle for all of
/// them. Hidden when there's nothing new.
class DiscoverSection extends ConsumerWidget {
  const DiscoverSection({super.key});

  /// A big cover, as Apple Music's lead shelves: most of a phone's width.
  static double cardSize(BuildContext context) => (MediaQuery.sizeOf(context).width * 0.56).clamp(180.0, 240.0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(discoverProvider);
    final size = cardSize(context);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(items: null),
          SkeletonShelf(size: size),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(items: null),
          InlineError(message: 'New songs didn’t load. $e', onRetry: () => ref.invalidate(discoverProvider)),
        ],
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(items: items),
            HorizontalShelf(
              height: size + captionExtent(context),
              itemCount: items.length,
              itemBuilder: (context, i) => _DiscoverCard(items: items, index: i, size: size),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _play(BuildContext context, WidgetRef ref, List<DiscoverItem> items,
    {DiscoverItem? from, bool shuffle = false}) async {
  var ok = false;
  try {
    ok = await ref.read(discoverPlayerProvider).play(items, from: from, shuffle: shuffle);
  } catch (_) {}
  if (!ok && context.mounted) showToast(context, 'Couldn’t load these songs. Check your connection and try again.');
}

/// Title 1 and a line on what's here; Shuffle and Play once there's music.
class _Header extends ConsumerWidget {
  final List<DiscoverItem>? items;
  const _Header({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final list = items;
    final fromCharts = list?.where((i) => i.fromCharts).length ?? 0;
    final line = list == null
        ? 'Fresh from the charts, and songs you haven’t played yet.'
        : [
            if (fromCharts > 0) '$fromCharts new from the charts',
            if (list.length - fromCharts > 0) '${list.length - fromCharts} never played',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('New in Your Library', style: t.title1)),
          const SizedBox(height: Space.xxs),
          Text(line, style: t.footnote),
          if (list != null && list.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            // Paired capsules (DESIGN.md): Play filled, Shuffle tinted, equal halves.
            Row(
              children: [
                Expanded(
                  child: TintedButton(
                    glyph: NaviGlyph.play,
                    label: 'Play',
                    filled: true,
                    height: 50,
                    onTap: () => _play(context, ref, list),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TintedButton(
                    glyph: NaviGlyph.shuffle,
                    label: 'Shuffle',
                    height: 50,
                    onTap: () => _play(context, ref, list, shuffle: true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiscoverCard extends ConsumerWidget {
  final List<DiscoverItem> items;
  final int index;
  final double size;
  const _DiscoverCard({required this.items, required this.index, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = items[index];
    return MediaCard(
      title: item.title,
      subtitle: '${item.artist} · ${item.reason}',
      artUrl: ref.read(subsonicServiceProvider).getCoverArtUrl(item.songId),
      size: size,
      onTap: () {
        HapticFeedback.lightImpact();
        _play(context, ref, items, from: item);
      },
    );
  }
}
