import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../logic/jam_controller.dart';
import '../logic/social_providers.dart';
import 'social_screen.dart';

/// A line on Home while this phone is in a Jam, to get back to it. It also
/// picks up a Jam the account is already in after an app restart.
class JamBanner extends ConsumerStatefulWidget {
  const JamBanner({super.key});

  @override
  ConsumerState<JamBanner> createState() => _JamBannerState();
}

class _JamBannerState extends ConsumerState<JamBanner> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(jamControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(jamControllerProvider.select((s) {
      final j = s.jam;
      return j == null ? null : (j.code, j.members.length, j.current?.title);
    }));
    final invites = ref.watch(invitationCountProvider);
    if (summary == null && invites == 0) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final headline = summary == null ? 'Sessions' : 'In a Jam · ${summary.$1}';
    final detail = summary == null
        ? (invites == 1 ? '1 invitation waiting' : '$invites invitations waiting')
        : (summary.$3 == null ? '${summary.$2} listening' : '${summary.$2} listening · ${summary.$3}');
    return CupertinoClickable(
      onTap: () => navigateInApp(context, const SocialScreen()),
      scaleFactor: 0.99,
      semanticLabel: '$headline, $detail. Open.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
        child: Row(children: [
          NaviIcon(NaviGlyph.group, size: 22, color: t.accent),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: t.headline),
              Text(
                detail,
                style: t.footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
