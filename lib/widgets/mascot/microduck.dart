import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import 'microduck_painter.dart';
import 'microduck_pose.dart';

/// Microduck at a fixed [size], animated by a single [Ticker].
///
/// The ticker only runs while the pose moves, the route is visible
/// ([TickerMode] mutes it off-screen), the app is in the foreground, and
/// reduced motion is off. It writes to a [ValueNotifier] only when the
/// pose's own frame rate says a new frame is worth painting (a standing duck
/// repaints 12 times a second, a dancing one every frame), and only the
/// painter listens, so nothing rebuilds.
class Microduck extends StatefulWidget {
  final MicroduckPose pose;
  final double size;

  /// Line colour; defaults to the theme's primary text colour.
  final Color? color;

  /// Tempo to hop to while dancing; null bobs gently at a steady pace.
  final int? bpm;
  final bool facingRight;

  const Microduck({
    super.key,
    required this.pose,
    this.size = 24,
    this.color,
    this.bpm,
    this.facingRight = true,
  });

  @override
  State<Microduck> createState() => _MicroduckState();
}

class _MicroduckState extends State<Microduck> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_onTick);
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
    final fps = widget.pose.fps;
    final frame = elapsed.inMicroseconds * fps ~/ Duration.microsecondsPerSecond;
    if (frame == _frame) return;
    _frame = frame;
    _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bpm = widget.bpm;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: MicroduckPainter(
          pose: widget.pose,
          time: _time,
          color: widget.color ?? ThemeTokens.of(context).textPrimary,
          beat: bpm == null ? 0.6 : 60 / bpm,
          energy: bpm == null ? 0.5 : 1,
          facingRight: widget.facingRight,
        ),
      ),
    );
  }
}
