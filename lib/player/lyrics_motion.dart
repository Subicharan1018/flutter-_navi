import 'dart:async';
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
  static const double restScale = 0.9;

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

  /// Furthest a line leans away, in radians, reached [tiltReach] lines out.
  /// Lines below the sung one lean back at their bottom edge, lines above at
  /// their top edge, so the page reads as the inside of a slow drum: depth from
  /// geometry, never from blur.
  static const double maxTilt = 0.62;
  static const double tiltReach = 3;
  static const double perspective = 0.0011;

  /// Signed lean (radians) by signed distance; 0 on the sung line.
  static double tiltFor(double d) => (d / tiltReach).clamp(-1.0, 1.0) * maxTilt;

  /// The full per-line transform: perspective, lean, then scale. Applied about
  /// the line's left-centre, so the sung line never swings sideways.
  static Matrix4 transformFor(double d) {
    final s = scaleFor(d);
    // The sung line stays a plain affine matrix: no perspective divide to rasterise.
    if (d == 0) return Matrix4.identity();
    return Matrix4.identity()
      ..setEntry(3, 2, perspective)
      ..rotateX(tiltFor(d))
      ..scaleByDouble(s, s, 1, 1);
  }

  static const _opacityAt = [1.0, 0.40, 0.31, 0.25, 0.21, 0.18, 0.16];

  /// Opacity by distance; lines already sung fade a little further.
  static double opacityFor(double d) {
    final a = d.abs().clamp(0.0, maxDistance.toDouble());
    final lo = a.floor();
    final hi = a.ceil();
    final base = lo == hi ? _opacityAt[lo] : _opacityAt[lo] + (_opacityAt[hi] - _opacityAt[lo]) * (a - lo);
    final behind = d < 0 ? 1 - 0.3 * (-d).clamp(0.0, 1.0) : 1.0;
    return base * behind;
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

/// Wraps one lyric line and glides its lean, scale and alpha whenever its
/// [distance] from the sung line changes.
///
/// One controller per line, ticking only while that line is moving. [builder]
/// gets the current alpha (0..1) to fold into its text colours; text only
/// changes colour, so it repaints but never relays out.
class LyricLineMotion extends StatefulWidget {
  final int distance;
  final Widget Function(BuildContext context, double alpha) builder;
  final Alignment alignment;

  const LyricLineMotion({
    super.key,
    required this.distance,
    required this.builder,
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
    // No blur and no Opacity layer: the line is lean-and-scale transformed, and
    // its alpha reaches the text through [LyricLineMotion.builder] as colour.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final d = _d;
          return Transform(
            transform: LyricsMotion.transformFor(d),
            alignment: widget.alignment,
            child: widget.builder(context, LyricsMotion.opacityFor(d)),
          );
        },
      ),
    );
  }
}
