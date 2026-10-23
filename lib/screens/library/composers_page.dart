import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/composer.dart';
import '../../providers/composer_provider.dart';
import '../../utils/format.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/ui/large_title_page.dart';
import '../../widgets/ui/media.dart';
import '../../widgets/ui/states.dart';
import '../composer_screen.dart';
import '../../core/theme.dart';

/// The round monogram-free glyph tile that stands in for a composer portrait.
class ComposerGlyph extends StatelessWidget {
  final double size;
  const ComposerGlyph({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.bgElevated, shape: BoxShape.circle),
      child: Icon(CupertinoIcons.music_mic, size: size * 0.4, color: t.textMuted),
    );
  }
}

/// One composer row: glyph, name, song count. Shared by Library and Search.
class ComposerRow extends StatelessWidget {
  final Composer composer;
  final bool showSeparator;
  final VoidCallback? onBeforeOpen;
  const ComposerRow({super.key, required this.composer, this.showSeparator = true, this.onBeforeOpen});

  @override
  Widget build(BuildContext context) {
    return CollectionRow(
      title: composer.name,
      subtitle: songCount(composer.songCount),
      leading: const ComposerGlyph(),
      showSeparator: showSeparator,
      onTap: () {
        onBeforeOpen?.call();
        navigateInApp(context, ComposerScreen(composerKey: composer.key, name: composer.name));
      },
    );
  }
}

/// Library › Composers: every music director in the library, A–Z.
class ComposersPage extends ConsumerWidget {
  const ComposersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composers = ref.watch(composersProvider);
    return LargeTitlePage(
      title: 'Composers',
      slivers: composers.when(
        loading: () => const [SliverFillRemaining(hasScrollBody: false, child: LoadingState())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageState.error(
              title: 'Couldn’t load composers',
              onRetry: () => ref.invalidate(composersProvider),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageState(
                    icon: CupertinoIcons.music_mic,
                    title: 'No composers yet',
                    message: 'Songs with a composer tag appear here by music director.',
                  ),
                ),
              ]
            : [
                SliverFixedExtentList(
                  itemExtent: 62,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => ComposerRow(composer: list[i], showSeparator: i < list.length - 1),
                    childCount: list.length,
                  ),
                ),
              ],
      ),
    );
  }
}
