import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/states.dart';
import '../../listen/data/listen_models.dart';
import '../logic/taste_providers.dart';

/// Settings > Taste: everything you told NaviVibe never to recommend, grouped
/// by songs, artists and composers, with Undo on each.
class TasteScreen extends ConsumerWidget {
  const TasteScreen({super.key});

  static const _titles = {
    TasteKind.song: 'Songs',
    TasteKind.artist: 'Artists',
    TasteKind.composer: 'Composers',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tasteExclusionsProvider);
    final list = async.asData?.value;
    return LargeTitlePage(
      title: 'Taste',
      clearPlayer: false,
      onRefresh: () => ref.refresh(tasteExclusionsProvider.future),
      slivers: [
        if (list != null && list.isNotEmpty)
          SliverList.list(children: [
            const SizedBox(height: Space.sm),
            for (final kind in TasteKind.values)
              if (list.any((e) => e.kind == kind))
                GroupedSection(
                  header: _titles[kind],
                  footer: kind == TasteKind.values.last
                      ? 'Left out of Discover, your weekly mix, Flow, playlist suggestions and Smart Shuffle.'
                      : null,
                  children: [
                    for (final e in list.where((e) => e.kind == kind)) _Row(entry: e),
                  ],
                ),
          ])
        else
          SliverToBoxAdapter(
            child: async.when(
              loading: () => const LoadingState(),
              error: (e, _) => MessageState.error(
                title: 'Your list didn’t load',
                onRetry: () => ref.invalidate(tasteExclusionsProvider),
              ),
              data: (_) => const MessageState(
                art: EmptyArtKind.noResults,
                title: 'Nothing is blocked',
                message: 'Open a song’s ⋯ menu and choose Never recommend to keep a song, artist or composer out of your mixes.',
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  final TasteExclusion entry;
  const _Row({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return GroupedRow(
      title: entry.label,
      trailing: Semantics(
        button: true,
        label: 'Allow ${entry.label} again',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            try {
              await ref.read(tasteExclusionsProvider.notifier).remove(entry);
              if (context.mounted) showToast(context, '${entry.label} can be recommended again');
            } catch (_) {
              if (context.mounted) showToast(context, 'Couldn’t undo that. Try again.');
            }
          },
          child: SizedBox(
            height: 44,
            child: Center(child: Text('Undo', style: t.body.copyWith(color: t.accent))),
          ),
        ),
      ),
    );
  }
}
