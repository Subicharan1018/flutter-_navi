import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'microduck_mesh.dart';
import 'microduck_painter.dart';
import 'microduck_pose.dart';
import 'microduck_rig.dart';

/// The Microduck robot at a fixed square [size], animated by a single
/// [Ticker].
///
/// The ticker only runs while the app is in the foreground, the route is
/// visible ([TickerMode] mutes it off-screen) and reduced motion is off. It
/// writes to a [ValueNotifier] only when the pose's own frame rate says a new
/// frame is worth painting (a standing robot repaints 24 times a second, a
/// dancing one every frame), and only the painter listens, so nothing
/// rebuilds.
///
/// With [interactive] the robot hops when tapped and turns its head toward a
/// finger resting on it.
class Microduck extends StatefulWidget {
  final MicroduckPose pose;
  final double size;
  final MicroduckSkin skin;

  /// Tempo to dance to; null uses [defaultDanceBpm].
  final int? bpm;

  /// Which way it walks.
  final bool facingRight;
  final bool interactive;

  const Microduck({
    super.key,
    required this.pose,
    this.size = 72,
    this.skin = MicroduckSkin.white,
    this.bpm,
    this.facingRight = true,
    this.interactive = false,
  });

  @override
  State<Microduck> createState() => _MicroduckState();
}

class _MicroduckState extends State<Microduck> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<double> _time = ValueNotifier(0);
  final MicroduckInput _input = MicroduckInput();
  late final Ticker _ticker = createTicker(_onTick);
  double _now = 0;
  int _frame = -1;
  bool _foreground = true;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(Microduck old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) _frame = -1;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _sync();
  }

  /// Runs the ticker only when something would move.
  void _sync() {
    final shouldRun = _foreground && !_reduced;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
    if (_reduced) _time.value = 0;
  }

  void _onTick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // Full rate while it is reacting to a finger, whatever the pose.
    final fps = _now < _input.activeUntil ? 60 : widget.pose.fps;
    final frame = elapsed.inMicroseconds * fps ~/ Duration.microsecondsPerSecond;
    if (frame == _frame) return;
    _frame = frame;
    _time.value = _now;
  }

  void _look(Offset p) {
    final s = widget.size;
    _input
      ..lookX = ((p.dx / s) * 2 - 1).clamp(-1.0, 1.0)
      ..lookY = (1 - (p.dy / s) * 2).clamp(-1.0, 1.0)
      ..lookUntil = double.infinity;
  }

  void _down(PointerDownEvent e) {
    if (_reduced) return;
    _input.tapAt = _now;
    _look(e.localPosition);
  }

  void _up(PointerEvent e) => _input.lookUntil = _now + 0.4;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: MicroduckPainter(
          pose: widget.pose,
          time: _time,
          input: _input,
          skin: widget.skin,
          bpm: widget.bpm ?? defaultDanceBpm,
          facingRight: widget.facingRight,
        ),
      ),
    );
    if (!widget.interactive) return paint;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: (e) => _look(e.localPosition),
      onPointerUp: _up,
      onPointerCancel: _up,
      child: paint,
    );
  }
}
