import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/download_provider.dart';
import '../../../services/cache_settings_service.dart';
import '../../../services/play_cache.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';

/// Bytes the played-songs cache uses; refreshes when files come or go.
final playCacheBytesProvider = FutureProvider.autoDispose<int>((ref) {
  final cache = PlayCache.instance;
  void listener() => ref.invalidateSelf();
  cache.revision.addListener(listener);
  ref.onDispose(() => cache.revision.removeListener(listener));
  return cache.sizeBytes();
});

/// "Cached songs": how much room recently played songs take, the limit, and
/// a button to clear them. Downloads are separate and never touched here.
class PlayCacheSection extends ConsumerStatefulWidget {
  const PlayCacheSection({super.key});

  @override
  ConsumerState<PlayCacheSection> createState() => _PlayCacheSectionState();
}

class _PlayCacheSectionState extends ConsumerState<PlayCacheSection> {
  int _limitMb = CacheSettingsService().getMusicCacheMaxMb();
  bool _clearing = false;

  static String _label(int mb) => mb >= 1000 ? '${mb ~/ 1000} GB' : '$mb MB';

  Future<void> _chooseLimit() async {
    final pick = await showPlatformSheet<int>(
      context: context,
      title: 'Cache Limit',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetGroup(children: [
          for (final mb in CacheSettingsService.musicCacheSizeChoicesMb)
            SheetAction(
              label: _label(mb),
              icon: mb == _limitMb ? NaviGlyph.check : null,
              onTap: () => Navigator.of(ctx).pop(mb),
              keepOpen: true,
            ),
        ]),
      ),
    );
    if (pick == null) return;
    await CacheSettingsService().setMusicCacheMaxMb(pick);
    if (!mounted) return;
    setState(() => _limitMb = pick);
    await PlayCache.instance.evict(); // a lower limit takes effect now
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await PlayCache.instance.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    showToast(context, 'Cached songs cleared');
  }

  @override
  Widget build(BuildContext context) {
    final bytes = ref.watch(playCacheBytesProvider).asData?.value;
    final size = bytes == null ? '—' : ref.read(offlineServiceProvider).formatSize(bytes);
    return GroupedSection(
      header: 'Cached Songs',
      footer: 'Songs you play are kept so going back to them needs no data. '
          'The oldest are removed first when the limit is reached.',
      children: [
        GroupedRow(title: 'Cache Size', icon: NaviGlyph.signal, value: size, showChevron: false),
        GroupedRow(title: 'Cache Limit', icon: NaviGlyph.signal, value: _label(_limitMb), onTap: _chooseLimit),
        GroupedRow(
          title: 'Clear Cached Songs',
          destructive: true,
          showChevron: false,
          onTap: _clearing || (bytes ?? 0) == 0 ? null : _clear,
        ),
      ],
    );
  }
}
