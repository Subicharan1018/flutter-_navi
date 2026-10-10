import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/player_provider.dart';
import 'player_controls.dart';

// =============================================================================
// Shuffle and repeat flanking the transport on the wide (desktop) player,
// where there's room. Phones follow Apple Music and keep them in the queue.
// Active state is full opacity plus a dot underneath — legible over any
// album colour without introducing a second accent hue on the artwork.
// =============================================================================

class _ModeGlyph extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color color;
  final double scale;

  const _ModeGlyph({
    required this.icon,
    required this.active,
    required this.semanticLabel,
    required this.onTap,
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? color : color.withValues(alpha: 0.55);
    return Semantics(
      toggled: active,
      child: GlyphButton(
        size: 48 * scale,
        semanticLabel: semanticLabel,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 5),
            Icon(icon, size: 24 * scale, color: c),
            const SizedBox(height: 3),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShuffleModeButton extends ConsumerWidget {
  final Color color;
  final double scale;
  const ShuffleModeButton({super.key, this.color = Colors.white, this.scale = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(playerProvider.select((s) => s.shuffleMode));
    return _ModeGlyph(
      icon: CupertinoIcons.shuffle,
      active: on,
      semanticLabel: on ? 'Shuffle on' : 'Shuffle off',
      onTap: () => ref.read(playerProvider.notifier).toggleShuffle(),
      color: color,
      scale: scale,
    );
  }
}

/// Off → repeat one → repeat all → off, matching `PlayerNotifier.cycleRepeat`.
class RepeatModeButton extends ConsumerWidget {
  final Color color;
  final double scale;
  const RepeatModeButton({super.key, this.color = Colors.white, this.scale = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerProvider.select((s) => s.repeatMode));
    return _ModeGlyph(
      icon: mode == LoopMode.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
      active: mode != LoopMode.off,
      semanticLabel: switch (mode) {
        LoopMode.off => 'Repeat off',
        LoopMode.one => 'Repeat this song',
        LoopMode.all => 'Repeat queue',
      },
      onTap: () => ref.read(playerProvider.notifier).cycleRepeat(),
      color: color,
      scale: scale,
    );
  }
}
