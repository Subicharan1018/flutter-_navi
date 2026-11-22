import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/horizontal_shelf.dart';
import '../../../widgets/ui/media.dart';
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import '../logic/rotation_providers.dart';

/// Home's "Back in rotation" shelf: songs you loved and haven't played for
/// two months, with the reason under each. Hidden until there are some.
class BackInRotationSection extends ConsumerWidget {
  static const double _cover = 150;
  const BackInRotationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(backInRotationProvider).asData?.value ?? const <ListenPick>[];
    if (picks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Back in Rotation'),
        HorizontalShelf(
          height: _cover + captionExtent(context),
          itemCount: picks.length,
          itemBuilder: (context, i) {
            final p = picks[i];
            return MediaCard(
              title: p.title,
              subtitle: p.why.isEmpty ? p.artist : p.why,
              artUrl: ref.read(subsonicServiceProvider).getCoverArtUrl(p.songId),
              size: _cover,
              onTap: () {
                HapticFeedback.lightImpact();
                playBackInRotation(context, ref, picks, from: p);
              },
            );
          },
        ),
      ],
    );
  }
}

/// Plays the shelf from [from]; says so when none of its songs could be loaded.
Future<void> playBackInRotation(BuildContext context, WidgetRef ref, List<ListenPick> picks, {required ListenPick from}) async {
  var ok = false;
  try {
    final songs = await ref.read(listenSongsProvider).loadPicks(picks);
    final start = songs.indexWhere((s) => s.id == from.songId);
    if (songs.isNotEmpty) {
      await ref.read(playerProvider.notifier).setQueue(songs, start < 0 ? 0 : start, playlistName: 'Back in Rotation');
      ok = true;
    }
  } catch (_) {}
  if (!ok && context.mounted) showToast(context, 'Couldn’t load these songs. Check your connection and try again.');
}
