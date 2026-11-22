import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/play_route.dart';
import '../providers/player_provider.dart';
import '../widgets/ui/action_sheet.dart' show showToast, showToastWithAction;

/// Says where a tap on a song or "Play" went ("Playing on Windows PC", with a
/// "Play here" action) and why a send to another device failed. Wrap one widget
/// that stays on screen while more than one device is signed in (the mini player).
class PlayNotices extends ConsumerWidget {
  final Widget child;
  const PlayNotices({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(playNoticeProvider.select((n) => n.seq), (_, _) {
      final n = ref.read(playNoticeProvider);
      final message = n.message;
      if (message == null) return;
      if (n.canPlayHere) {
        showToastWithAction(
          context,
          message,
          actionLabel: 'Play here',
          onAction: () => ref.read(playerProvider.notifier).playHereInstead(),
        );
      } else {
        showToast(context, message);
      }
    });
    return child;
  }
}
