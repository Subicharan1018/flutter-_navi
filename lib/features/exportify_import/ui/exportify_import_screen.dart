import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/exportify_models.dart';
import '../logic/exportify_providers.dart';
import 'exportify_result_screen.dart';

/// Settings › Import a Spotify playlist. Export the playlist as a CSV at exportify.net, choose the
/// file here, and see what is already in the library and what goes on the wishlist.
class ExportifyImportScreen extends ConsumerWidget {
  const ExportifyImportScreen({super.key});

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final imp = await ref.read(exportifyUploadProvider.notifier).pickAndUpload();
    if (imp != null && context.mounted) {
      navigateInApp(context, ExportifyResultScreen(initial: imp), title: imp.name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final upload = ref.watch(exportifyUploadProvider);
    final imports = ref.watch(exportifyImportsProvider);
    final gutter = pageGutter(context);

    return LargeTitlePage(
      title: 'Import a Playlist',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
            child: Text(
              'Export your Spotify playlist as a CSV at exportify.net, then choose the file here. '
              'Songs you already have are matched; the rest become a wishlist you can fetch a little at a time.',
              style: t.subheadline,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: upload.busy
                ? _Reading(name: upload.busyName!)
                : TintedButton(
                    glyph: NaviGlyph.doc,
                    label: 'Choose CSV File',
                    filled: true,
                    onTap: () => _choose(context, ref),
                  ),
          ),
        ),
        if (upload.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, Space.md, gutter, 0),
              child: Text(upload.error!, style: t.footnote.copyWith(color: t.danger)),
            ),
          ),
        const SliverToBoxAdapter(child: SectionHeader(title: 'Your imports')),
        ...imports.when(
          loading: () => const [SliverToBoxAdapter(child: _ImportsSkeleton())],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(
                title: 'Couldn’t load your imports',
                onRetry: () => ref.invalidate(exportifyImportsProvider),
              ),
            ),
          ],
          data: (list) => list.isEmpty
              ? const [
                  SliverToBoxAdapter(
                    child: MessageState(
                      icon: NaviGlyph.playlist,
                      title: 'No imports yet',
                      message: 'Choose a CSV from Exportify to see what you already have.',
                    ),
                  ),
                ]
              : [
                  SliverToBoxAdapter(
                    child: GroupedSection(children: [
                      for (final i in list)
                        GroupedRow(
                          title: i.name,
                          subtitle: importLine(i),
                          onTap: () => navigateInApp(context, ExportifyResultScreen(initial: i), title: i.name),
                        ),
                    ]),
                  ),
                ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}

/// "2,119 in your library · 4,803 on your wishlist"
String importLine(ExportifySummary i) =>
    '${groupThousands(i.inLibrary)} in your library · ${groupThousands(i.onWishlist)} on your wishlist';

class _Reading extends StatelessWidget {
  final String name;
  const _Reading({required this.name});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: Space.md),
          Flexible(
            child: Text('Matching “$name”…', style: t.subheadline, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _ImportsSkeleton extends StatelessWidget {
  const _ImportsSkeleton();

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: Space.sm),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(children: [Expanded(child: SkeletonBox(width: double.infinity, height: 40))]),
            ),
        ],
      ),
    );
  }
}
