import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive, showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../data/exportify_models.dart';
import '../logic/exportify_providers.dart';
import 'exportify_fetch_screen.dart';

/// What an import found: how many songs, how many are already in the library, what is on the
/// wishlist and what fetching it would cost. One primary action: fetch the wishlist.
/// Opens with [initial] (from the upload or the list) and keeps itself fresh from the server.
class ExportifyResultScreen extends ConsumerStatefulWidget {
  final ExportifySummary initial;
  const ExportifyResultScreen({super.key, required this.initial});

  @override
  ConsumerState<ExportifyResultScreen> createState() => _ExportifyResultScreenState();
}

class _ExportifyResultScreenState extends ConsumerState<ExportifyResultScreen> {
  bool _making = false;
  String? _problem;

  Future<void> _makePlaylist(ExportifySummary imp) async {
    setState(() {
      _making = true;
      _problem = null;
    });
    try {
      await ref.read(exportifyPlaylistMakerProvider)(imp);
      if (mounted) showToast(context, 'Playlist “${imp.name}” is in your library');
    } on OnlineFetchException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } catch (_) {
      if (mounted) setState(() => _problem = 'Couldn’t make the playlist. Try again.');
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _remove(ExportifySummary imp) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove this import?',
      message: 'Your wishlist for “${imp.name}” is deleted and any fetch of it stops. '
          'Songs already in your library stay.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(exportifyApiProvider).delete(imp.id);
      ref.invalidate(exportifyImportsProvider);
      if (mounted) Navigator.of(context).maybePop();
    } on OnlineFetchException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final imp = ref.watch(exportifyDetailProvider(widget.initial.id)).value ?? widget.initial;
    final gutter = pageGutter(context);
    final free = imp.freeGb;
    final canMakePlaylist = imp.inLibrary > 0;

    return LargeTitlePage(
      title: imp.name,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${groupThousands(imp.unique)} songs', style: t.largeTitle),
                const SizedBox(height: Space.lg),
                _Figure(groupThousands(imp.inLibrary), 'already in your library'),
                _Figure(groupThousands(imp.onWishlist), 'on your wishlist'),
                if (imp.onWishlist > 0) _Figure('about ${formatGb(imp.wishlistGb)}', 'to fetch'),
                if (free != null) _Figure(formatGb(free), 'free on the server'),
                const SizedBox(height: Space.md),
                for (final line in notes(imp)) Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(line, style: t.footnote),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: imp.onWishlist == 0
                ? Text('Everything on this list is already in your library.', style: t.subheadline)
                : TintedButton(
                    glyph: NaviGlyph.download,
                    label: imp.hasFetch ? 'Open Wishlist' : 'Fetch My Wishlist',
                    filled: true,
                    onTap: () => navigateInApp(context, ExportifyFetchScreen(id: imp.id), title: 'Wishlist'),
                  ),
          ),
        ),
        if (_problem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, Space.md, gutter, 0),
              child: Text(_problem!, style: t.footnote.copyWith(color: t.danger)),
            ),
          ),
        SliverToBoxAdapter(
          child: GroupedSection(children: [
            if (canMakePlaylist)
              GroupedRow(
                title: imp.playlistId == null ? 'Make a Playlist' : 'Update the Playlist',
                subtitle: '${groupThousands(imp.inLibrary)} songs you already have, in the file’s order',
                icon: NaviGlyph.playlist,
                trailing: _making ? const CupertinoActivityIndicator() : null,
                showChevron: false,
                onTap: _making ? null : () => _makePlaylist(imp),
              ),
            GroupedRow(title: 'Remove This Import', destructive: true, showChevron: false, onTap: () => _remove(imp)),
          ]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}

/// The footnotes under the figures: what was folded, guessed or too big.
List<String> notes(ExportifySummary imp) {
  final folded = imp.duplicates + imp.skippedRows;
  final free = imp.freeGb;
  return [
    if (folded > 0)
      '${groupThousands(imp.duplicates)} repeats and ${groupThousands(imp.skippedRows)} rows without a title were left out.',
    if (imp.maybeOwned > 0)
      '${groupThousands(imp.maybeOwned)} wishlist songs have a version in your library at a different length. They stay on the wishlist.',
    if (imp.noIsrc > 0) '${groupThousands(imp.noIsrc)} had no ISRC and were matched by title and artist.',
    if (free != null && imp.onWishlist > 0 && imp.wishlistGb > free)
      'The wishlist is bigger than the free space. Fetching starts with the most popular songs and pauses before the disk gets low.',
  ];
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;
  const _Figure(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: t.title2),
          const SizedBox(width: Space.sm),
          Flexible(child: Text(label, style: t.subheadline)),
        ],
      ),
    );
  }
}
