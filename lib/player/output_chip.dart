import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../services/notification_pills.dart';
import '../services/output_route.dart';
import '../services/pill_prefs.dart';
import '../widgets/art/navi_icons.dart';

/// Where sound is going, as one quiet line in Now Playing. Shown on Android
/// only, and only when the sound is not coming from the phone speaker.
class OutputChip extends ConsumerWidget {
  const OutputChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(outputRouteProvider);
    if (route.kind == RouteKind.speaker || !Pill.output.on) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final glyph = switch (route.kind) {
      RouteKind.bluetooth || RouteKind.wired || RouteKind.usb => NaviGlyph.headphones,
      _ => NaviGlyph.speaker,
    };
    return Semantics(
      label: 'Playing on ${route.label}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.xs),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          NaviIcon(glyph, size: 12, color: t.textMuted),
          const SizedBox(width: Space.xs + 2),
          Flexible(child: Text(route.label, style: t.caption1.copyWith(color: t.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
