import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/media.dart';
import '../logic/fetch_queue_providers.dart';
import '../logic/online_fetch_providers.dart';
import 'fetch_queue_sheet.dart';

/// One tap puts a whole playlist link on the download queue (a Deezer
/// playlist chart, say). It says when it's queued and opens the queue on tap.
class QueuePlaylistButton extends ConsumerStatefulWidget {
  final String link;
  const QueuePlaylistButton({super.key, required this.link});

  @override
  ConsumerState<QueuePlaylistButton> createState() => _QueuePlaylistButtonState();
}

enum _Phase { idle, sending, queued }

class _QueuePlaylistButtonState extends ConsumerState<QueuePlaylistButton> {
  _Phase _phase = _Phase.idle;

  Future<void> _queue() async {
    setState(() => _phase = _Phase.sending);
    final problem = await queuePlaylistLink(ref.read(onlineFetchApiProvider), widget.link);
    if (!mounted) return;
    setState(() => _phase = problem == null ? _Phase.queued : _Phase.idle);
    if (problem != null) showToast(context, problem);
  }

  @override
  Widget build(BuildContext context) => switch (_phase) {
        _Phase.idle => TintedButton(glyph: NaviGlyph.download, label: 'Add to Download Queue', onTap: _queue),
        _Phase.sending => const TintedButton(label: 'Adding to the queue…'),
        _Phase.queued => TintedButton(
            glyph: NaviGlyph.checkCircle,
            label: 'In the queue · View',
            onTap: () => showFetchQueue(context),
          ),
      };
}
