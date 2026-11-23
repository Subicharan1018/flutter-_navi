import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/motion.dart';

/// A slow ambient loop for a card's own surface, built so it costs nothing
/// when nobody can see it.
///
/// It runs only while ALL of these hold: Motion is Full ([MotionContext.motionFull],
/// which already folds in Reduced motion and the TV/low-RAM defaults), the
/// route's tickers are enabled ([TickerMode]), the app is resumed, and the
/// card is on screen (checked a few times a second, not per frame). The value
/// handed to [builder] is a 0→1 phase that repeats every [period], updated at
/// about 30 frames a second.
///
/// When it is not running, [builder] gets [stillPhase]: design that frame to
/// look finished. The animated part belongs inside [builder] and should be a
/// transform or opacity of a layer that is already rasterised, under its own
/// [RepaintBoundary] (this widget adds one).
class AmbientLoop extends StatefulWidget {
  final Duration period;

  /// The phase shown when the loop is not running.
  final double stillPhase;
  final Widget Function(BuildContext context, double phase) builder;

  /// Widget tests hold ambient loops still (a looping ticker never lets
  /// `pumpAndSettle` finish). A test of the loop itself sets this to true.
  @visibleForTesting
  static bool debugForceRun = false;

  static bool get _heldByTests => WidgetsBinding.instance.runtimeType.toString().contains('Test') && !debugForceRun;

  const AmbientLoop({
    super.key,
    required this.builder,
    this.period = const Duration(seconds: 14),
    this.stillPhase = 0.25,
  });

  @override
  State<AmbientLoop> createState() => AmbientLoopState();
}

class AmbientLoopState extends State<AmbientLoop> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _frame = Duration(milliseconds: 33);

  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Timer? _visibility;
  Duration _lastPaint = Duration.zero;
  bool _onScreen = true;
  bool _resumed = true;

  /// Whether the loop is currently ticking (read by tests).
  @visibleForTesting
  bool get running => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    _phase.value = widget.stillPhase;
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AmbientLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  bool get _wanted => !AmbientLoop._heldByTests && context.motionFullNow && TickerMode.valuesOf(context).enabled && _resumed && _onScreen;

  void _sync() {
    final want = !AmbientLoop._heldByTests && context.motionFullNow && TickerMode.valuesOf(context).enabled && _resumed;
    if (want) {
      // Poll visibility a few times a second instead of every frame.
      _visibility ??= Timer.periodic(const Duration(milliseconds: 400), (_) => _checkVisible());
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
    } else {
      _visibility?.cancel();
      _visibility = null;
      _stop();
    }
  }

  void _checkVisible() {
    if (!mounted) return;
    final box = context.findRenderObject();
    var on = false;
    if (box is RenderBox && box.attached && box.hasSize) {
      final view = View.maybeOf(context);
      final size = view == null ? null : view.physicalSize / view.devicePixelRatio;
      final top = box.localToGlobal(Offset.zero);
      on = size == null ||
          (top.dy < size.height && top.dy + box.size.height > 0 && top.dx < size.width && top.dx + box.size.width > 0);
    }
    _onScreen = on;
    if (_wanted) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (_ticker.isActive) return;
    _lastPaint = Duration.zero;
    _ticker.start();
  }

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
    if (_phase.value != widget.stillPhase) _phase.value = widget.stillPhase;
  }

  void _tick(Duration elapsed) {
    if (elapsed - _lastPaint < _frame) return;
    _lastPaint = elapsed;
    _phase.value = (elapsed.inMicroseconds % widget.period.inMicroseconds) / widget.period.inMicroseconds;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibility?.cancel();
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe, so flipping Motion in Settings re-evaluates at once.
    context.motionFull;
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _phase,
        builder: (context, phase, _) => widget.builder(context, phase),
      ),
    );
  }
}
