import 'package:flutter/widgets.dart';

/// A row that fades up 14 px into place when it first appears, staggered by
/// its index (first eight rows only; ease-out 320 ms). A new mix therefore
/// arrives as a cascade; a row that is merely re-ordered keeps its State (the
/// caller keys it by song) and does not replay. Reduced motion: shown at once.
class RiseIn extends StatelessWidget {
  final int index;
  final Widget child;
  const RiseIn({super.key, required this.index, required this.child});

  static const int _staggered = 8;

  @override
  Widget build(BuildContext context) {
    if (index >= _staggered || MediaQuery.disableAnimationsOf(context)) return child;
    final delay = index * 45;
    const body = 320;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: delay + body),
      curve: Interval(delay / (delay + body), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
    );
  }
}
