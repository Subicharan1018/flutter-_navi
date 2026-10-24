import 'package:flutter/widgets.dart';

/// Drives one 0→1 animation a single time and hands it to [builder].
///
/// This is the one controller behind every animated chart and story card: a
/// card owns exactly one [PlayOnce], and everything inside reads sub-ranges of
/// its value with `Interval`. With reduced motion the value is 1 from the
/// first frame, so the finished picture shows with no movement.
///
/// An external [progress] (a story card's own clock) replaces the internal
/// controller, so a primitive works both free-standing and inside a card.
class PlayOnce extends StatefulWidget {
  final Duration duration;
  final Duration delay;
  final Curve curve;

  /// Drive from outside instead of starting on mount.
  final Animation<double>? progress;
  final Widget Function(BuildContext context, Animation<double> progress) builder;

  const PlayOnce({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
    this.progress,
  });

  @override
  State<PlayOnce> createState() => _PlayOnceState();
}

class _PlayOnceState extends State<PlayOnce> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _curved;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.progress != null || _started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c = AnimationController(vsync: this, duration: widget.duration, value: 1);
    } else {
      _c = AnimationController(vsync: this, duration: widget.duration);
      if (widget.delay == Duration.zero) {
        _c!.forward();
      } else {
        Future<void>.delayed(widget.delay, () {
          if (mounted) _c?.forward();
        });
      }
    }
    _curved = CurvedAnimation(parent: _c!, curve: widget.curve);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: widget.builder(context, widget.progress ?? _curved!));
}

/// The eased value of [t] between [begin] and [end] (all 0..1): how far a
/// staggered part of a card has got, with no extra controller or listener.
double sliceOf(double t, double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
    Interval(begin, end, curve: curve).transform(t);
