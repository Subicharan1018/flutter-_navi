import 'package:flutter/material.dart';

import '../../utils/platform_utils.dart';

// =============================================================================
// tv_frame.dart — one fixed layout canvas for every TV.
//
// TVs report their own densities (a 1080p panel at 320 dpi is only 960 × 540
// logical px; at 213 dpi it is 1280 × 720). Laying the app out at whatever the
// TV says makes everything 1.3–2× too big or small from one set to the next.
// So on a TV the whole app (routes, sheets, dialogs) is laid out on a
// 1280 × 720 canvas, Android TV's own "tvdpi" reference, and scaled to the
// screen. A 16 dp body is then 24 px on a 1080p set; rails, rows and focus
// rings keep the same proportions everywhere.
//
// Touch targets, hit testing and the on-screen keyboard keep working: the
// scale is an ordinary transform and [MediaQuery] reports the canvas.
// =============================================================================

class TvFrame extends StatelessWidget {
  final Widget child;
  const TvFrame({super.key, required this.child});

  /// Logical width every TV lays out at.
  static const double designWidth = 1280;

  /// Android TV's recommended overscan-safe margins (48 × 27 px at 1080p),
  /// in canvas units. Exposed as [MediaQueryData.padding] so screens that use
  /// a SafeArea keep inside it; full-bleed art may still run to the edge.
  static const EdgeInsets overscan = EdgeInsets.symmetric(horizontal: 32, vertical: 18);

  /// A little larger than phone type: it is read from a sofa.
  static const double textScale = 1.1;

  /// The canvas for a screen of [real] logical size.
  static Size canvasFor(Size real) {
    final scale = real.width / designWidth;
    return Size(designWidth, real.height / scale);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isTv) return child;
    final mq = MediaQuery.of(context);
    final real = mq.size;
    if (real.isEmpty) return child;
    final scale = real.width / designWidth;
    final canvas = canvasFor(real);
    return SizedBox(
      width: real.width,
      height: real.height,
      child: FittedBox(
        fit: BoxFit.fill, // the canvas has the screen's aspect ratio, so this is a pure scale
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: canvas,
          child: MediaQuery(
            data: mq.copyWith(
              size: canvas,
              devicePixelRatio: mq.devicePixelRatio * scale,
              textScaler: const TextScaler.linear(textScale),
              padding: overscan,
              viewPadding: overscan,
              viewInsets: mq.viewInsets / scale,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
