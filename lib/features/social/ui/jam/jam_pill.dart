import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/app_scaffold.dart' show AppTab, selectAppTab;
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/shell/dock_glass.dart';
import '../../logic/jam_controller.dart';

/// "Jam live" above the mini player while this phone is in a room. Tap to
/// open it. Takes no space otherwise.
class JamLivePill extends ConsumerWidget {
  const JamLivePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(jamControllerProvider.select((s) {
      final j = s.jam;
      return j == null ? null : (j.code, j.members.length, j.youAreHost);
    }));
    if (summary == null) return const SizedBox.shrink();
    final (code, people, host) = summary;
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs + 2),
      child: CupertinoClickable(
        onTap: () => selectAppTab(AppTab.jam),
        scaleFactor: 0.97,
        semanticLabel: 'Jam live, code $code, $people in the room. Open.',
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: DockGlass.of(context) ? const Color(0x14FFFFFF) : t.fill,
            borderRadius: BorderRadius.circular(Radii.capsule),
            border: Border.all(color: DockGlass.of(context) ? const Color(0x2BFFFFFF) : t.outline, width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            NaviIcon(NaviGlyph.jam, size: 18, color: t.textPrimary),
            const SizedBox(width: Space.sm),
            Text('Jam live', style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(width: Space.sm),
            Text('$code · $people${host ? ' · host' : ''}', style: t.footnote),
          ]),
        ),
      ),
    );
  }
}
