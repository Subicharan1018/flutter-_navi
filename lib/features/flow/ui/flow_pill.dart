import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../logic/flow_controller.dart';
import 'flow_section.dart' show flowLabel, showFlowMoodSheet;

/// Now Playing's Flow status: shown only while Flow feeds the queue. Tap for
/// the mood; Stop ends Flow and leaves the queue as it is. Drawn over the
/// artwork, so it uses the on-artwork tokens; each half is a 44-tall target
/// around the 32-tall capsule, and a long mood name shortens with an ellipsis.
class FlowPill extends ConsumerWidget {
  const FlowPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(flowProvider.select((s) => s.active));
    if (!active) return const SizedBox.shrink();
    final mood = ref.watch(flowProvider.select((s) => s.mood));
    final t = ThemeTokens.of(context);
    final label = flowLabel(mood);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: _Target(
            onTap: () => showFlowMoodSheet(context, ref),
            semanticLabel: '$label. Change mood',
            child: _Capsule(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NaviIcon(NaviGlyph.flow, size: 16, color: AppThemeTokens.onArtwork),
                  const SizedBox(width: Space.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.footnote.copyWith(color: AppThemeTokens.onArtwork, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.xs),
        _Target(
          onTap: ref.read(flowProvider.notifier).stop,
          semanticLabel: 'Stop Flow',
          child: _Capsule(
            child: Text('Stop', maxLines: 1, style: t.footnote.copyWith(color: AppThemeTokens.onArtworkDim)),
          ),
        ),
      ],
    );
  }
}

/// The 44-tall hit area around a capsule.
class _Target extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget child;
  const _Target({required this.onTap, required this.semanticLabel, required this.child});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: CupertinoClickable(onTap: onTap, semanticLabel: semanticLabel, child: Center(widthFactor: 1, child: child)),
      );
}

class _Capsule extends StatelessWidget {
  final Widget child;
  const _Capsule({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: AppThemeTokens.onArtworkGlass,
          borderRadius: BorderRadius.circular(Radii.capsule),
        ),
        child: Center(widthFactor: 1, child: child),
      );
}
