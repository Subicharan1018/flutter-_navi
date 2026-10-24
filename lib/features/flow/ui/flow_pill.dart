import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../logic/flow_controller.dart';
import 'flow_section.dart' show showFlowMoodSheet;

/// Now Playing's Flow status: shown only while Flow feeds the queue. Tap for
/// the mood; Stop ends Flow and leaves the queue as it is. White on the
/// artwork, like the rest of Now Playing.
class FlowPill extends ConsumerWidget {
  const FlowPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(flowProvider.select((s) => s.active));
    if (!active) return const SizedBox.shrink();
    final mood = ref.watch(flowProvider.select((s) => s.mood));
    final t = ThemeTokens.of(context);
    final label = mood == null ? 'Flow' : 'Flow · ${mood[0].toUpperCase()}${mood.substring(1)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoClickable(
            onTap: () => showFlowMoodSheet(context, ref),
            semanticLabel: '$label. Change mood',
            child: _Capsule(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NaviIcon(NaviGlyph.flow, size: 16, color: Colors.white),
                  const SizedBox(width: Space.xs),
                  Text(label, style: t.footnote.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          CupertinoClickable(
            onTap: ref.read(flowProvider.notifier).stop,
            semanticLabel: 'Stop Flow',
            child: _Capsule(
              child: Text('Stop', style: t.footnote.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ),
          ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  final Widget child;
  const _Capsule({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Radii.capsule),
        ),
        child: child,
      );
}
