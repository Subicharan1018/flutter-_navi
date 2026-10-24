import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/format.dart' show songCount;
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../logic/weekly_mix_providers.dart';
import 'weekly_mix_screen.dart';

/// Home's "Your Weekly Mix" shelf: the mix's own cover first (opens the page),
/// then its songs as covers. Hidden until the server has a mix with songs.
class WeeklyMixSection extends ConsumerWidget {
  static const double _cover = 150;
  const WeeklyMixSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklyMixProvider);
    void open() => navigateInApp(context, const WeeklyMixScreen());
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Your Weekly Mix', onTap: open),
          SizedBox(
            height: _cover + 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.only(right: Space.md),
                    child: SkeletonBox(width: _cover, height: _cover, radius: Radii.cover),
                  ),
              ],
            ),
          ),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Your Weekly Mix', onTap: open),
          InlineError(message: 'Your mix didn’t load. $e', onRetry: () => ref.invalidate(weeklyMixProvider)),
        ],
      ),
      data: (mix) {
        if (mix.items.isEmpty) return const SizedBox.shrink();
        final shown = mix.items.take(20).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: 'Your Weekly Mix', onTap: open),
            SizedBox(
              height: _cover + 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                itemCount: shown.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return MediaCard(
                      title: 'Weekly Mix',
                      subtitle: [
                        if (weekLabel(mix.weekOf).isNotEmpty) weekLabel(mix.weekOf),
                        songCount(mix.items.length),
                      ].join(' · '),
                      art: SizedBox.square(dimension: _cover, child: weeklyMixCover(mix)),
                      size: _cover,
                      onTap: open,
                    );
                  }
                  final p = shown[i - 1];
                  return MediaCard(
                    title: p.title,
                    subtitle: p.artist,
                    artUrl: ref.read(subsonicServiceProvider).getCoverArtUrl(p.songId),
                    size: _cover,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      playWeeklyMix(context, ref, mix, from: p);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
