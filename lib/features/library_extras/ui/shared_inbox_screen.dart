import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/playlist.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../../screens/playlist_details_screen.dart';
import '../../../utils/format.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../logic/library_extras_providers.dart';

/// "Shared with you" inbox: other people's playlists, the new ones first, each
/// with its owner and size and two actions: Make a Copy (the way to edit one)
/// and Dismiss (hide it from the inbox on this device; the server keeps it).
class SharedInboxScreen extends ConsumerStatefulWidget {
  const SharedInboxScreen({super.key});

  @override
  ConsumerState<SharedInboxScreen> createState() => _SharedInboxScreenState();
}

class _SharedInboxScreenState extends ConsumerState<SharedInboxScreen> {
  /// What was new when the inbox opened: it stays marked while you read it, and
  /// counts as seen from then on.
  late final Set<String> _newOnOpen;

  @override
  void initState() {
    super.initState();
    final inbox = ref.read(sharedInboxProvider);
    _newOnOpen = {for (final e in inbox.entries) if (e.isNew) e.playlist.id};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sharedInboxStateProvider.notifier).markSeen(_newOnOpen);
    });
  }

  Future<void> _copy(Playlist p) async {
    try {
      final copy = await ref.read(playlistControllerProvider).makeCopy(p);
      if (mounted) showToast(context, 'Copied to “${copy.name}”');
    } catch (_) {
      if (mounted) showToast(context, 'Couldn’t make a copy. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final inbox = ref.watch(sharedInboxProvider);
    final svc = ref.read(subsonicServiceProvider);
    Widget action(String label, VoidCallback onTap, {bool primary = false}) => CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          minimumSize: const Size(44, 36),
          onPressed: onTap,
          child: Text(label, style: t.subheadline.copyWith(color: primary ? t.accent : t.textSecondary, fontWeight: FontWeight.w600)),
        );
    return LargeTitlePage(
      title: 'Shared with you',
      onRefresh: () async => ref.invalidate(playlistsProvider),
      slivers: [
        if (inbox.isEmpty)
          const SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.share,
              title: 'Nothing shared with you',
              message: 'Playlists other people share on your server show up here.',
            ),
          )
        else
          SliverList.builder(
            itemCount: inbox.entries.length,
            itemBuilder: (context, i) {
              final e = inbox.entries[i];
              final p = e.playlist;
              final isNew = _newOnOpen.contains(p.id);
              final owner = (p.owner ?? '').isEmpty ? null : p.owner;
              return Column(
                key: ValueKey(p.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CollectionRow(
                    title: p.name,
                    subtitle: [?owner, songCount(p.songCount)].join(' · '),
                    leading: CoverArt(
                      url: (p.coverArt ?? '').isEmpty ? null : svc.getCoverArtUrl(p.coverArt),
                      size: 56,
                      radius: Radii.cover,
                      placeholderIcon: NaviGlyph.playlist,
                    ),
                    badge: isNew ? Text('New', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w700)) : null,
                    showSeparator: false,
                    onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p), title: p.name),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: pageGutter(context) + 56),
                    child: Row(children: [
                      action('Make a Copy', () => _copy(p), primary: true),
                      action('Dismiss', () => ref.read(sharedInboxStateProvider.notifier).dismiss(p.id)),
                    ]),
                  ),
                  Container(
                    margin: EdgeInsets.only(left: pageGutter(context) + 56 + Space.md),
                    height: 0.5,
                    color: t.outline,
                  ),
                ],
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}
