import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/remote_queue_provider.dart';
import '../widgets/desktop_dialogs.dart';
import '../widgets/ui/action_sheet.dart' show showToast;
import 'now_playing_style.dart';
import 'queue_pane.dart';

/// The playing device's queue, opened from this remote: the same queue pane
/// as on the device that plays, with every edit sent there.
Future<void> showRemoteQueue(BuildContext context, {String? hostName}) {
  final height = MediaQuery.sizeOf(context).height;
  return showPlatformSheet<void>(
    context: context,
    title: hostName == null ? 'Queue' : 'Queue on $hostName',
    maxHeight: 720,
    builder: (ctx) => SizedBox(
      height: (height * 0.72).clamp(320.0, 640.0),
      child: QueuePane(style: NowPlayingStyle.fromTokens(ThemeTokens.of(ctx)), showCurrent: true),
    ),
  );
}

/// Shows why a queue edit sent from this remote was undone, wherever it was
/// made (the queue, a song menu, search). Wrap one widget that stays on screen
/// while this device is a remote (the remote mini player).
class RemoteQueueNotices extends ConsumerWidget {
  final Widget child;
  const RemoteQueueNotices({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(remoteQueueProvider.select((s) => s.noticeSeq), (_, _) {
      final notice = ref.read(remoteQueueProvider).notice;
      if (notice != null) showToast(context, notice);
    });
    return child;
  }
}
