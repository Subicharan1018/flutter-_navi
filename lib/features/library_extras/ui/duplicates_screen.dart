import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/duplicates.dart';
import '../logic/library_extras_providers.dart';

/// Library › Merge Duplicates. Groups of the same song, album or artist found in
/// the synced library. Pick the one to keep; hide the extra songs on this device
/// or copy a clean-up list. Nothing is deleted, here or on the server.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  /// Chosen keeper per group, keyed by the group's suggested keeper.
  final Map<String, String> _keeper = {};

  Future<void> _export(DuplicateScan scan) async {
    final text = buildCleanupExport([...scan.songs, ...scan.albums, ...scan.artists], _keeper);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, 'Clean-up list copied');
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final scan = ref.watch(duplicateScanProvider);
    final hidden = ref.watch(hiddenSongsProvider);
    return LargeTitlePage(
      title: 'Merge Duplicates',
      slivers: [
        ...scan.when(
          loading: () => const [SliverToBoxAdapter(child: LoadingState())],
          error: (_, _) => [
            SliverToBoxAdapter(child: MessageState.error(title: 'Couldn’t read the library', onRetry: () => ref.invalidate(duplicateScanProvider))),
          ],
          data: (s) {
            if (s.total == 0 && hidden.isEmpty) {
              return const [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.checkCircle,
                    title: 'No duplicates found',
                    message: 'Songs, albums and artists that repeat show up here.',
                  ),
                ),
              ];
            }
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), Space.md),
                  child: Text(
                    'Nothing is deleted. Hiding removes the extra songs from your Songs list on this device; the clean-up list is for you to tidy the server by hand.',
                    style: t.footnote,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pageGutter(context) - Space.md),
                  child: Wrap(children: [
                    if (s.total > 0) _TextButton('Copy Clean-up List', () => _export(s), primary: true),
                    if (hidden.isNotEmpty)
                      _TextButton('Restore ${hidden.length} hidden', () => ref.read(hiddenSongsProvider.notifier).restore(hidden.toList())),
                  ]),
                ),
              ),
              _section('Songs', s.songs, canHide: true),
              _section('Albums', s.albums, canHide: false),
              _section('Artists', s.artists, canHide: false),
            ];
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }

  Widget _section(String title, List<DupGroup> groups, {required bool canHide}) {
    if (groups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(child: SectionHeader(title: '$title · ${groups.length}')),
      SliverList.builder(
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          return _GroupView(
            key: ValueKey('${g.kind.name}:${g.suggestedKeeperId}'),
            group: g,
            keeperId: _keeper[g.suggestedKeeperId] ?? g.suggestedKeeperId,
            canHide: canHide,
            onPick: (id) => setState(() => _keeper[g.suggestedKeeperId] = id),
          );
        },
      ),
    ]);
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _TextButton(this.label, this.onTap, {this.primary = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      minimumSize: const Size(44, 36),
      onPressed: onTap,
      child: Text(label, style: t.subheadline.copyWith(color: primary ? t.accent : t.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}

class _GroupView extends ConsumerWidget {
  final DupGroup group;
  final String keeperId;
  final bool canHide;
  final ValueChanged<String> onPick;
  const _GroupView({super.key, required this.group, required this.keeperId, required this.canHide, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final hidden = ref.watch(hiddenSongsProvider);
    final extras = extrasOf(group, keeperId);
    final pending = [for (final id in extras) if (!hidden.contains(id)) id];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final item in group.items)
        CupertinoClickable(
          onTap: () => onPick(item.id),
          scaleFactor: 0.99,
          semanticLabel: '${item.title}, ${item.detail}${item.id == keeperId ? ', keeping' : ''}',
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pageGutter(context), vertical: Space.sm),
            child: Row(children: [
              NaviIcon(
                item.id == keeperId ? NaviGlyph.checkCircle : NaviGlyph.ring,
                size: 22,
                color: item.id == keeperId ? t.accent : t.textMuted,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    item.subtitle.isEmpty ? item.title : '${item.title} · ${item.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: hidden.contains(item.id) ? t.textMuted : t.textPrimary),
                  ),
                  Text(item.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                ]),
              ),
              if (hidden.contains(item.id)) NaviIcon(NaviGlyph.eyeOff, size: 16, color: t.textMuted),
            ]),
          ),
        ),
      if (canHide && pending.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(left: pageGutter(context) - Space.md + 22 + Space.md),
          child: _TextButton(
            pending.length == 1 ? 'Hide the Extra' : 'Hide ${pending.length} Extras',
            () => ref.read(hiddenSongsProvider.notifier).hide(pending),
          ),
        ),
      Container(margin: EdgeInsets.only(left: pageGutter(context)), height: 0.5, color: t.outline),
    ]);
  }
}
