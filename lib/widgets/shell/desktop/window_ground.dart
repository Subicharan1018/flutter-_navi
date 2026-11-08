import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../ui/dock_ground.dart';
import '../../../player/artwork.dart' show coverPaletteProvider;
import '../../../providers/player_provider.dart';

/// The palette of the song that is playing, or null when nothing plays (or its
/// colours have not been read yet). The ONE source of the desktop window's tint:
/// pages follow it too, so the rail, top bar, page, side panel and player bar
/// never show two different colours.
final windowPaletteProvider = Provider<AlbumPalette?>((ref) {
  final id = ref.watch(playerProvider.select((s) => s.currentSong?.coverArt));
  if (id == null || id.isEmpty) return null;
  return ref.watch(coverPaletteProvider(id)).asData?.value;
});

/// The desktop window's ground, with the tokens to match: ONE tint from the
/// playing song's art, else (nothing playing) the page's own cover, painted as
/// one gradient. Put the whole window (rail, top bar, page, panel, player bar)
/// inside it, with each of them transparent.
class DesktopWindowGround extends ConsumerWidget {
  final Widget child;
  const DesktopWindowGround({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final playing = ref.watch(windowPaletteProvider);
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, pageGround, _) {
        final tint = playing?.ground ?? pageGround;
        final tokens = tint == null ? t : AppThemeTokens.tinted(playing ?? AlbumPalette.fallback, tint);
        return ThemeTokens(
          tokens: tokens,
          child: WindowGround(tint: tint, fallback: t.bgBase, child: child),
        );
      },
    );
  }
}

/// One soft vertical gradient behind the whole desktop window: [tint] at the
/// top, deepening toward the bottom edge. Every pane above it is transparent,
/// so there is no seam anywhere. Eases when the tint changes; without a tint it
/// is plain [fallback].
class WindowGround extends StatelessWidget {
  final Color? tint;
  final Color fallback;
  final Widget child;
  const WindowGround({super.key, required this.tint, required this.fallback, required this.child});

  /// How far the bottom edge deepens toward black.
  static const double deepen = 0.45;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint ?? fallback),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, c, child) {
        final top = c ?? tint ?? fallback;
        final bottom = tint == null ? top : Color.lerp(top, const Color(0xFF000000), deepen)!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
