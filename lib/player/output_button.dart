import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../providers/player_provider.dart';
import '../providers/session_sync_provider.dart';
import '../services/output_route.dart';
import '../widgets/art/navi_icons.dart';
import 'devices_sheet.dart';
import 'player_controls.dart' show GlyphButton;

/// What the middle button under Now Playing says: where the sound is coming
/// out, as a glyph and a name. [label] is null when there is nothing worth
/// saying (a platform that doesn't report outputs, with no other device).
@immutable
class OutputBadge {
  final NaviGlyph glyph;
  final String? label;
  const OutputBadge(this.glyph, this.label);

  @override
  bool operator ==(Object other) => other is OutputBadge && other.glyph == glyph && other.label == label;
  @override
  int get hashCode => Object.hash(glyph, label);
}

NaviGlyph outputGlyph(RouteKind kind) => switch (kind) {
      RouteKind.speaker => NaviGlyph.phone,
      RouteKind.wired || RouteKind.bluetooth || RouteKind.usb => NaviGlyph.headphones,
      RouteKind.hdmi || RouteKind.car => NaviGlyph.speaker,
    };

/// Another device playing wins over this device's own route: the sound is there.
OutputBadge outputBadge({
  required bool passive,
  required String? hostName,
  required OutputRoute? route,
  required bool sharing,
}) {
  if (passive) return OutputBadge(NaviGlyph.speaker, hostName ?? 'Another device');
  if (route != null) return OutputBadge(outputGlyph(route.kind), route.label);
  return OutputBadge(NaviGlyph.headphones, sharing ? 'This device' : null);
}

/// Devices button with the output's name under it, as Apple Music names the
/// AirPlay target. Tapping opens the devices sheet, where the listener can
/// switch outputs or move playback to another device.
class OutputButton extends ConsumerWidget {
  /// Height of the name's line, kept on phones so the row never jumps when the
  /// route arrives.
  static const double captionHeight = 16;

  final double size;
  final Color? restFill;
  final bool reserveCaption;

  /// A small mark on the glyph (the sleep timer's moon).
  final Widget? mark;

  const OutputButton({super.key, required this.size, this.restFill, this.reserveCaption = false, this.mark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerProvider.select((s) => s.syncMode));
    final badge = outputBadge(
      passive: mode == SyncMode.passive,
      hostName: ref.watch(playerProvider.select((s) => s.remoteActiveDeviceName)),
      route: ref.watch(outputRouteProvider),
      sharing: mode == SyncMode.activeHere && ref.watch(syncDevicesProvider.select((d) => (d.asData?.value.length ?? 0) >= 2)),
    );
    final passive = mode == SyncMode.passive;
    final color = passive ? Colors.white : Colors.white.withValues(alpha: 0.72);
    final move = context.motionFull ? Motion.standard : Duration.zero;
    final label = badge.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphButton(
          size: size,
          restFill: restFill,
          semanticLabel: label == null ? 'Devices' : 'Playing on $label. Devices',
          selected: passive,
          onTap: () => showDevicesSheet(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedSwitcher(
                duration: move,
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: child)),
                child: NaviIcon(badge.glyph, key: ValueKey(badge.glyph), size: 24, color: color),
              ),
              ?mark,
            ],
          ),
        ),
        if (label != null || reserveCaption)
          SizedBox(
            height: captionHeight,
            // A new output's name rises into place under the glyph.
            child: AnimatedSwitcher(
              duration: move,
              switchInCurve: Motion.ease,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a), child: child),
              ),
              child: label == null
                  ? const SizedBox.shrink()
                  : ExcludeSemantics(
                      key: ValueKey(label),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: naviText(11, FontWeight.w600, Colors.white.withValues(alpha: passive ? 0.95 : 0.66)),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
