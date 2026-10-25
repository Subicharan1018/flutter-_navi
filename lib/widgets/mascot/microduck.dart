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
/// frame is worth painting (a standing robot repaints 30 times a second, a
/// dancing one every frame), and only the painter listens, so nothing
/// rebuilds.
///
/// With [interactive]: a tap makes it hop (or wave, alternately), a finger
/// resting on it makes it look, and a long press makes it bow.
///
/// Reactions from the outside: change [startleToken] (for instance to the
/// current song's id) and it jumps; set [love] true and a heart appears on its
/// screen.
class Microduck extends StatefulWidget {
  final MicroduckPose pose;
  final double size;
  final MicroduckSkin skin;

  /// Tempo to dance to; null uses [defaultDanceBpm].
  final int? bpm;

  /// Which way it walks.
  final bool facingRight;
  final bool interactive;

  /// How far up from the bottom edge the touch area stops (see the build).
  final double hitInsetBottom;
  final Object? startleToken;
  final bool love;

  /// While dancing: the song's playback position (read every frame, so the
  /// beat holds across seeks and pauses) and where its first beat falls.
  final Duration Function()? positionSource;
  final double beatOffset;

  /// Waiting on an answer: head cocked, loading wave on the screen. When it
  /// ends the robot celebrates.
  final bool thinking;

  /// Saying something: head nods, the screen shows a voice meter.
  final bool talking;

  /// A quick tap (not a long press), after the hop starts.
  final VoidCallback? onTap;

  const Microduck({
    super.key,
    required this.pose,
    this.size = 72,
    this.skin = MicroduckSkin.white,
    this.bpm,
    this.facingRight = true,
    this.interactive = false,
    this.hitInsetBottom = 0,
    this.startleToken,
    this.love = false,
    this.positionSource,
    this.beatOffset = 0,
    this.thinking = false,
    this.talking = false,
    this.onTap,
  });

  @override
  State<Microduck> createState() => _MicroduckState();
}

class _MicroduckState extends State<Microduck> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _longPress = 0.45;

  final ValueNotifier<double> _time = ValueNotifier(0);
  final MicroduckInput _input = MicroduckInput();
  late final Ticker _ticker = createTicker(_onTick);
  double _now = 0;
  int _frame = -1;
  bool _foreground = true;
  bool _reduced = false;

  double _downAt = 0;
  bool _pressing = false, _bowed = false;

  @override
  void initState() {
    super.initState();
    _input
      ..thinking = widget.thinking
      ..talking = widget.talking
      ..beatOffset = widget.beatOffset;
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
    if (!_reduced) {
      if (widget.startleToken != old.startleToken && old.startleToken != null) _input.startleAt = _now;
      if (widget.love && !old.love) _input.loveAt = _now;
      if (old.thinking && !widget.thinking) {
        // The answer is in: a happy hop and a heart.
        _input
          ..tapAt = _now
          ..tapCount = 0
          ..loveAt = _now;
      }
    }
    _input
      ..thinking = widget.thinking
      ..talking = widget.talking
      ..beatOffset = widget.beatOffset;
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
    final source = widget.positionSource;
    if (source != null && widget.pose == MicroduckPose.dance) {
      _input.audioPos = source().inMicroseconds / Duration.microsecondsPerSecond;
    } else {
      _input.audioPos = null;
    }
    if (_pressing && !_bowed && _now - _downAt > _longPress) {
      _bowed = true;
      _input.bowAt = _now;
    }
    // Full rate while it is reacting, whatever the pose.
    final busy = widget.thinking || widget.talking;
    final fps = _now < _input.activeUntil || _pressing || busy ? 60 : widget.pose.fps;
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
    _pressing = true;
    _bowed = false;
    _downAt = _now;
    _look(e.localPosition);
  }

  void _up(PointerEvent e) {
    if (_pressing && !_bowed && _now - _downAt <= _longPress && e is PointerUpEvent) {
      _input
        ..tapAt = _now
        ..tapCount += 1;
      widget.onTap?.call();
    }
    _pressing = false;
    _input.lookUntil = _now + 0.4;
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
    // The touch area is drawn separately so its bottom edge can stop short of
    // the feet: where the robot stands on a bar, the bar keeps its own touches.
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        children: [
          paint,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: widget.hitInsetBottom,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: (e) => _look(e.localPosition),
              onPointerUp: _up,
              onPointerCancel: _up,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
