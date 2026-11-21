import 'package:flutter/widgets.dart';

import '../core/album_palette.dart';
import '../core/motion.dart';
import 'artwork.dart';
import 'cover_quality.dart';

/// Now Playing's full-bleed look: the cover fills the top of the screen and
/// its lower part fades into the page's opaque tint, with the title sitting
/// on the fade. No blur and no shader mask: the fade is one plain gradient.

/// Height of the title block (title, artist, buttons) that sits on the fade.
/// The fade must already be nearly opaque where this starts.
const double kTitleZone = 86;

/// How opaque the tint must be at the top of the title block, so white text
/// holds 4.5:1 over even a pure white cover (see `full_bleed_art_test.dart`).
const double kFadeAtTitle = 0.86;

/// Tint opacity [d] dp above the bottom of the art, for a title block of
/// [zone] dp. Zero up in the picture, [kFadeAtTitle] where the title starts,
/// one at the very bottom, where the art meets the page.
double fadeAlphaAt(double d, {double zone = kTitleZone}) {
  final stops = <(double, double)>[
    (zone + 176, 0),
    (zone + 104, 0.30),
    (zone + 34, 0.72),
    (zone, kFadeAtTitle),
    (zone / 2, 0.95),
    (0, 1),
  ];
  if (d >= stops.first.$1) return 0;
  for (var i = 1; i < stops.length; i++) {
    final (d1, a1) = stops[i];
    if (d >= d1) {
      final (d0, a0) = stops[i - 1];
      return a0 + (a1 - a0) * ((d0 - d) / (d0 - d1));
    }
  }
  return 1;
}

/// The page behind the player while the art is full-bleed: the cover's
/// lighter ground at the top, its deepest tone at the bottom. Opaque.
LinearGradient nowPlayingTint(AlbumPalette p) {
  final top = p.ground;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [top, Color.lerp(top, p.deep, 0.6)!, p.deep],
    stops: const [0, 0.55, 1],
  );
}

/// The page's colour [y] (0 top .. 1 bottom) down the screen: what the art
/// has to fade into where it ends.
Color nowPlayingTintAt(AlbumPalette p, double y) {
  final top = p.ground;
  final mid = Color.lerp(top, p.deep, 0.6)!;
  return y <= 0.55 ? Color.lerp(top, mid, y / 0.55)! : Color.lerp(mid, p.deep, (y - 0.55) / 0.45)!;
}

/// The cover at full bleed: the picture, the fade into [tint] and a scrim
/// behind the status bar and grabber. Fixed size; the stage positions it.
class FullBleedCover extends StatelessWidget {
  final NowPlayingCoverRequest request;
  final double width;
  final double height;

  /// The page colour where the art ends.
  final Color tint;

  /// How far the status bar, grabber and chips reach down: the black scrim
  /// behind them covers this much.
  final double scrimHeight;

  /// 1 with the art filling the screen; falls to 0 as it shrinks into the
  /// pane header, taking the fade and scrim with it.
  final double fade;

  const FullBleedCover({
    super.key,
    required this.request,
    required this.width,
    required this.height,
    required this.tint,
    required this.scrimHeight,
    this.fade = 1,
  });

  static const List<double> _ds = [kTitleZone + 176, kTitleZone + 104, kTitleZone + 34, kTitleZone, kTitleZone / 2, 0];

  @override
  Widget build(BuildContext context) {
    final stops = <double>[for (final d in _ds) (1 - d / height).clamp(0.0, 1.0)];
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(
            url: request.url,
            cacheKey: request.cacheKey,
            width: width,
            height: height,
            cacheWidth: request.width,
          ),
          if (fade > 0) ...[
            // The tint follows the page's colour when the palette arrives a
            // beat after the picture, in step with the backdrop.
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tint),
              duration: context.motionFull ? kTintFade : Duration.zero,
              builder: (context, color, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [for (final d in _ds) (color ?? tint).withValues(alpha: fadeAlphaAt(d) * fade)],
                    stops: stops,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: scrimHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.fromRGBO(0, 0, 0, 0.58 * fade), const Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How long the page and the art's fade take to follow a new cover's tint.
const Duration kTintFade = Duration(milliseconds: 600);

/// The page behind full-bleed art: opaque, never a shader. It eases to the
/// next cover's tint instead of snapping.
class NowPlayingBackdrop extends StatelessWidget {
  final AlbumPalette palette;
  const NowPlayingBackdrop({super.key, required this.palette});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.motionFull ? kTintFade : Duration.zero,
      decoration: BoxDecoration(gradient: nowPlayingTint(palette)),
    );
  }
}
