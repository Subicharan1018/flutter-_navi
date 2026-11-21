import 'package:flutter/widgets.dart';

/// What a two-finger touchpad swipe asks for.
enum TouchpadSwipe { none, back, forward }

/// Decides whether a precision-touchpad pan was a swipe to go back or forward:
/// mostly horizontal, long enough and quick. A slower or shorter drag is
/// scrolling (a shelf that scrolls sideways must not leave the page).
class TouchpadSwipeRecogniser {
  static const double minDistance = 200;
  static const Duration maxDuration = Duration(milliseconds: 450);
  static const double horizontalBias = 2.5; // |dx| must beat |dy| by this much

  Duration _begin = Duration.zero;
  Duration _last = Duration.zero;
  Offset _pan = Offset.zero;

  void start(Duration at) {
    _begin = at;
    _last = at;
    _pan = Offset.zero;
  }

  /// [pan] is the total movement since [start], as precision touchpads report it.
  void update(Duration at, Offset pan) {
    _last = at;
    _pan = pan;
  }

  TouchpadSwipe end() {
    final quick = _last - _begin <= maxDuration;
    final longEnough = _pan.dx.abs() >= minDistance;
    final horizontal = _pan.dx.abs() >= _pan.dy.abs() * horizontalBias;
    final result = quick && longEnough && horizontal
        ? (_pan.dx > 0 ? TouchpadSwipe.back : TouchpadSwipe.forward)
        : TouchpadSwipe.none;
    _pan = Offset.zero;
    return result;
  }
}

/// Reports a two-finger touchpad swipe over [child] (Windows precision
/// touchpads: right = back, left = forward, as in a browser).
class TouchpadSwipeListener extends StatefulWidget {
  final ValueChanged<TouchpadSwipe> onSwipe;
  final Widget child;
  const TouchpadSwipeListener({super.key, required this.onSwipe, required this.child});

  @override
  State<TouchpadSwipeListener> createState() => _TouchpadSwipeListenerState();
}

class _TouchpadSwipeListenerState extends State<TouchpadSwipeListener> {
  final _swipe = TouchpadSwipeRecogniser();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent, // only watches; the page underneath still gets the events
      onPointerPanZoomStart: (e) => _swipe.start(e.timeStamp),
      onPointerPanZoomUpdate: (e) => _swipe.update(e.timeStamp, e.pan),
      onPointerPanZoomEnd: (_) {
        final s = _swipe.end();
        if (s != TouchpadSwipe.none) widget.onSwipe(s);
      },
      child: widget.child,
    );
  }
}
