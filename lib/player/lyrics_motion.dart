import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/widgets.dart';

/// The look of a lyric line as a function of how far it is from the sung one.
///
/// [d] is the signed distance in lines: 0 is the sung line, positive lines are
/// still to come, negative ones are behind. It is a double so a line can glide
/// between two distances; every value here is continuous in it.
///
/// Emphasis is a transform plus opacity plus a light blur, never a font-size
/// change, so text never reflows while it moves.
abstract final class LyricsMotion {
  /// Lines beyond this many places away all look (and rebuild) the same.
  static const int maxDistance = 6;

  /// Scale of a line that is not the sung one. The sung line is 1.0.
  static const double restScale = 0.82;

  /// Where the sung line's top sits, as a fraction of the pane's height.
  static const double anchor = 0.3;

  static const Duration glide = Duration(milliseconds: 520);

  /// A jump (tap, seek) moves quicker and in one piece, without the stagger.
  static const Duration seekGlide = Duration(milliseconds: 240);

  /// Each line further down the page starts this much later, up to [maxStagger].
  static const Duration staggerStep = Duration(milliseconds: 30);
  static const int maxStagger = 4;

  static const Curve curve = Curves.easeOutCubic;

  /// The scroll spring: critically damped, so the view settles without a bounce.
  static const SpringDescription scrollSpring = SpringDescription(mass: 1, stiffness: 170, damping: 26);
  static const SpringDescription seekSpring = SpringDescription(mass: 1, stiffness: 380, damping: 39);

  static double scaleFor(double d) => 1 - (1 - restScale) * d.abs().clamp(0.0, 1.0);

  static const _opacityAt = [1.0, 0.44, 0.34, 0.26, 0.20, 0.17, 0.16];

  /// Opacity by distance; lines already sung fade a little further.
  static double opacityFor(double d) {
    final a = d.abs().clamp(0.0, maxDistance.toDouble());
    final lo = a.floor();
    final hi = a.ceil();
    final base = lo == hi ? _opacityAt[lo] : _opacityAt[lo] + (_opacityAt[hi] - _opacityAt[lo]) * (a - lo);
    final behind = d < 0 ? 1 - 0.3 * (-d).clamp(0.0, 1.0) : 1.0;
    return base * behind;
  }

  /// Blur sigma by distance: none on the sung line, a little more per line
  /// away, so the page softens toward its edges.
  static double blurFor(double d) {
    final a = d.abs().clamp(0.0, 4.0);
    return a.clamp(0.0, 1.0) * 0.9 + (a - 1).clamp(0.0, 3.0) * 0.45;
  }

  /// How long line [to] waits before it starts moving from [from].
  static Duration staggerFor(int from, int to) {
    if (isSeek(from, to)) return Duration.zero;
    return staggerStep * to.clamp(0, maxStagger);
  }

  /// A change of more than one place is a jump, not the song moving on.
  static bool isSeek(int from, int to) => (to - from).abs() > 1;

  /// The scroll offset that puts a line whose top is [lineTop] (in scrollable
  /// content coordinates) and which is [lineHeight] tall at [alignment] of the
  /// [viewport], kept inside the scrollable range.
  static double scrollTarget({
    required double lineTop,
    required double lineHeight,
    required double viewport,
    required double minExtent,
    required double maxExtent,
    double alignment = anchor,
  }) {
    final raw = lineTop - (viewport - lineHeight) * alignment;
    return raw.clamp(minExtent, maxExtent < minExtent ? minExtent : maxExtent);
  }
}

/// Wraps one lyric line and glides its scale, opacity and blur whenever its
/// [distance] from the sung line changes.
///
/// One controller per line, ticking only while that line is moving; the child
/// is built once by the parent and reused every frame, so nothing but the
/// transform and layer properties change per frame.
class LyricLineMotion extends StatefulWidget {
  final int distance;
  final Widget child;
  final Alignment alignment;

  const LyricLineMotion({
    super.key,
    required this.distance,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  @override
  State<LyricLineMotion> createState() => _LyricLineMotionState();
}

class _LyricLineMotionState extends State<LyricLineMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late double _from = widget.distance.toDouble();
  late double _to = _from;
  Timer? _delay;

  double get _d => _from + (_to - _from) * LyricsMotion.curve.transform(_c.value);

  @override
  void didUpdateWidget(LyricLineMotion old) {
    super.didUpdateWidget(old);
    if (old.distance == widget.distance) return;
    _delay?.cancel();
    final here = _d; // pick up from wherever the line is right now
    _c.stop();
    _from = here;
    _to = widget.distance.toDouble();
    _c.value = 0;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || !TickerMode.valuesOf(context).enabled) {
      _from = _to;
      _c.value = 1;
      return;
    }
    final seek = LyricsMotion.isSeek(old.distance, widget.distance);
    _c.duration = seek ? LyricsMotion.seekGlide : LyricsMotion.glide;
    final wait = LyricsMotion.staggerFor(old.distance, widget.distance);
    if (wait == Duration.zero) {
      _c.forward(from: 0);
    } else {
      _delay = Timer(wait, () {
        if (mounted) _c.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final d = _d;
          Widget w = Transform.scale(scale: LyricsMotion.scaleFor(d), alignment: widget.alignment, child: child);
          final sigma = LyricsMotion.blurFor(d);
          if (sigma > 0.05) {
            w = ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
              child: w,
            );
          }
          return Opacity(opacity: LyricsMotion.opacityFor(d), child: w);
        },
      ),
    );
  }
}
