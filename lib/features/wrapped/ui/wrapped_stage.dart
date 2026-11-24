import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../film/film.dart';
import '../film/scenes.dart';
import 'wrapped_share_sheet.dart';

/// When a scene lands something you should feel it.
const _thumps = <String, List<double>>{
  'intro': [0.9, 2.9],
  'minutes': [1.5, 5.4],
  'number-one': [2.8, 3.9],
  'streak': [2.0, 5.2],
  'discovery': [1.0, 3.6],
  'personality': [1.9],
  'journey': [4.9],
  'best-day': [2.6, 4.6],
  'finale': [0.1, 2.4],
};

/// Plays the film and lets you touch it. Tap the edges to move, tap the middle to blast the swarm (or play the
/// scene), drag to stir, hold to pause, flick up from the bottom for how a number was worked out. Keys: arrows,
/// space, Esc. With reduced motion every scene is its still and nothing moves by itself.
class WrappedStage extends StatefulWidget {
  final WrappedFilm film;

  /// Shown inside the film, and on what is shared only when the switch is on.
  final String? name;
  final VoidCallback? onClose;

  /// Repaints when a cover arrives.
  final Listenable? arrivals;

  /// What the film is waiting for, said on the last scene there is so far; null once all of it is here.
  final String? waiting;

  /// 0..1 of that, or null when it cannot be counted yet.
  final double? progress;
  const WrappedStage({super.key, required this.film, this.name, this.onClose, this.arrivals, this.waiting, this.progress});

  @override
  State<WrappedStage> createState() => WrappedStageState();
}

class WrappedStageState extends State<WrappedStage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _beat = ValueNotifier(0);
  final FilmTouch _touch = FilmTouch();
  Duration _last = Duration.zero;
  int _index = 0;
  int? _from;
  double _fromT = 0;
  double _t = 0;
  int _thump = 0;
  bool _held = false;
  bool _busy = false;
  bool _reduced = false;
  Size _size = Size.zero;
  Offset? _start;

  @visibleForTesting
  int get index => _index;
  @visibleForTesting
  double get time => _t;
  @visibleForTesting
  FilmTouch get touch => _touch;

  List<FilmScene> get _scenes => widget.film.scenes;
  FilmScene get _scene => _scenes[_index];
  bool get _last_ => _index == _scenes.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _ticker.stop();
      _t = _scene.still;
      _from = null;
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _beat.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _touch.tick(dt);
    if (_start == null) {
      _touch.tiltX *= math.pow(0.05, dt).toDouble();
      _touch.tiltY *= math.pow(0.05, dt).toDouble();
    }
    if (!_held && !_busy) _t += dt;
    final cues = _thumps[_scene.id] ?? const [];
    while (_thump < cues.length && _t >= cues[_thump]) {
      _thump++;
      HapticFeedback.mediumImpact();
    }
    final end = _scene.id == 'guess' && _touch.guess != null ? _touch.guessAt + 3.6 : _scene.length;
    if (_t >= end && !_last_ && _start == null) {
      _go(_index + 1);
      return;
    }
    _beat.value++;
  }

  void _go(int to) {
    final target = to.clamp(0, _scenes.length - 1);
    if (target == _index && to > _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _from = _reduced || target == _index ? null : _index;
      _fromT = _t;
      _index = target;
      _t = _reduced ? _scenes[target].still : 0;
      _thump = 0;
      _touch
        ..scrubX = null
        ..spin = 0
        ..guess = null
        ..blasts.clear();
    });
  }

  void _hold(bool on) => _held = on;

  void _tap(Offset p) {
    final x = p.dx / _size.width;
    if (x < 0.16) return _go(_index - 1);
    if (x > 0.84) return _go(_index + 1);
    if (_scene.id == 'guess' && _touch.guess == null) {
      for (var k = 0; k < 3; k++) {
        if (GuessScene.card(_size, k, _t).inflate(14 * _size.width / 360).contains(p)) {
          final right = guessOrder(widget.film.data)[k] == 0;
          right ? HapticFeedback.heavyImpact() : HapticFeedback.vibrate();
          setState(() {
            _touch.guess = k;
            _touch.guessAt = _reduced ? _t - 2 : _t;
          });
          if (right) _touch.blasts.add((p, 0));
          return;
        }
      }
    }
    if (_reduced) return _go(_index + 1);
    if (_scene.id == 'top5') {
      final done = 1.0 + widget.film.data.songs.length * CountdownScene.beat;
      if (_t < done) {
        HapticFeedback.heavyImpact();
        _touch.blasts.add((p, 0));
        final next = _t < 1 ? 1.0 : 1.0 + (((_t - 1) ~/ CountdownScene.beat) + 1) * CountdownScene.beat;
        _t = next + 0.01;
        return;
      }
    }
    HapticFeedback.mediumImpact();
    _touch.blasts.add((p, 0));
  }

  void _panStart(Offset p) {
    _start = p;
    _touch.finger = p;
  }

  void _panUpdate(Offset p, Offset delta) {
    _touch.finger = _scene.drags ? null : p;
    final u = _size.width / 360;
    _touch.spin += delta.dx / (90 * u);
    _touch.tiltX = (_touch.tiltX + delta.dx / (130 * u)).clamp(-1.0, 1.0);
    _touch.tiltY = (_touch.tiltY + delta.dy / (160 * u)).clamp(-1.0, 1.0);
    if (_scene.drags) {
      final was = _touch.scrubX;
      _touch.scrubX = clamp01(p.dx / _size.width);
      final steps = switch (_scene.id) {
        'clock' => 24,
        'journey' => 12,
        _ => 0,
      };
      if (steps > 0 && was != null && (was * steps).floor() != (_touch.scrubX! * steps).floor()) HapticFeedback.selectionClick();
    }
    if (_reduced) _beat.value++;
  }

  void _panEnd(Velocity v) {
    final up = v.pixelsPerSecond.dy < -700 && v.pixelsPerSecond.dx.abs() < 500 && (_start?.dy ?? 0) > _size.height * 0.6;
    _start = null;
    _touch.finger = null;
    _touch.scrubX = null;
    if (up) _why();
  }

  Future<void> _why() async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.lightImpact();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => WrappedPanel(
        children: [
          Text('How this was worked out', style: ThemeTokens.of(context).headline.copyWith(color: kInk)),
          const SizedBox(height: Space.sm),
          Text(_scene.why(widget.film.data), style: ThemeTokens.of(context).body.copyWith(color: kDim, height: 1.4)),
        ],
      ),
    );
    _busy = false;
  }

  Future<void> _share() async {
    if (_busy) return;
    _busy = true;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => WrappedShareSheet(film: widget.film, index: _index, name: widget.name),
    );
    _busy = false;
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      _go(_index + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(_index - 1);
    } else if (k == LogicalKeyboardKey.space) {
      _hold(!_held);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _why();
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: LayoutBuilder(
          builder: (context, box) {
            // A tall stage on any window: a wide one shows it in the middle.
            final width = math.min(box.maxWidth, box.maxHeight * 0.62);
            _size = Size(width, box.maxHeight);
            return Center(
              child: SizedBox.fromSize(
                size: _size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      label: _scene.speech(widget.film.data),
                      onIncrease: () => _go(_index + 1),
                      onDecrease: () => _go(_index - 1),
                      increasedValue: 'Next',
                      decreasedValue: 'Previous',
                      value: 'Scene ${_index + 1} of ${_scenes.length}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _tap(d.localPosition),
                        onLongPressStart: (_) => _hold(true),
                        onLongPressEnd: (_) => _hold(false),
                        onLongPressCancel: () => _hold(false),
                        onPanStart: (d) => _panStart(d.localPosition),
                        onPanUpdate: (d) => _panUpdate(d.localPosition, d.delta),
                        onPanEnd: (d) => _panEnd(d.velocity),
                        onPanCancel: () => _panEnd(Velocity.zero),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            isComplex: true,
                            willChange: !_reduced,
                            painter: _FilmPainter(this, widget.arrivals == null ? _beat : Listenable.merge([_beat, widget.arrivals])),
                          ),
                        ),
                      ),
                    ),
                    _chrome(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    Widget button(NaviGlyph glyph, String label, VoidCallback onTap) => CupertinoClickable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 44,
        child: Center(child: NaviIcon(glyph, size: 20, color: kInk)),
      ),
    );
    final hint = _scene.hint;
    return Stack(
      children: [
        if (widget.waiting != null && _last_)
          Positioned(
            left: 48,
            right: 48,
            bottom: pad.bottom + 60,
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  children: [
                    Text(widget.waiting!, textAlign: TextAlign.center, style: ThemeTokens.of(context).callout.copyWith(color: kDim)),
                    const SizedBox(height: Space.sm),
                    SizedBox(
                      height: 3,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _WaitPainter(this, _beat, widget.progress),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          top: pad.top + Space.xs,
          left: Space.md,
          right: Space.xs,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 3,
                  child: RepaintBoundary(child: CustomPaint(painter: _ProgressPainter(this, _beat))),
                ),
              ),
              const SizedBox(width: Space.xs),
              button(NaviGlyph.share, 'Share', _share),
              if (widget.onClose != null) button(NaviGlyph.close, 'Close', widget.onClose!),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad.bottom,
          child: Center(
            child: CupertinoClickable(
              onTap: _why,
              semanticLabel: 'How this was worked out',
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text([?hint, 'Why?'].join('  ·  '), style: ThemeTokens.of(context).footnote.copyWith(color: const Color(0xFF86868C))),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilmPainter extends CustomPainter {
  final WrappedStageState s;
  _FilmPainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(ui.Canvas canvas, Size size) =>
      s.widget.film.paint(canvas, size, index: s._index, t: s._t, from: s._from, fromT: s._fromT, touch: s._touch, name: s.widget.name);

  @override
  bool shouldRepaint(_FilmPainter old) => true;
}

/// The wait, as a line: filling when it can be counted, a glint running along it when it cannot.
class _WaitPainter extends CustomPainter {
  final WrappedStageState s;
  final double? progress;
  _WaitPainter(this.s, Listenable repaint, this.progress) : super(repaint: repaint);

  @override
  void paint(ui.Canvas canvas, Size size) {
    const r = Radius.circular(2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = const Color(0xFF2C2C2E));
    final p = progress;
    final w = size.width * 0.25;
    final rect = p != null
        ? Rect.fromLTWH(0, 0, size.width * clamp01(p), size.height)
        : Rect.fromLTWH((size.width - w) * (0.5 - 0.5 * math.cos(s._t * 2.2)), 0, w, size.height);
    if (rect.width > 0) canvas.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..color = kInk);
  }

  @override
  bool shouldRepaint(_WaitPainter old) => old.progress != progress;
}

class _ProgressPainter extends CustomPainter {
  final WrappedStageState s;
  _ProgressPainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(ui.Canvas canvas, Size size) {
    const gap = 3.0;
    final n = s._scenes.length;
    final w = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final f = i < s._index ? 1.0 : (i == s._index ? clamp01(s._t / s._scene.length) : 0.0);
      final r = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = const Color(0xFF48484A));
      if (f > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, 0, w * f, size.height), const Radius.circular(2)), Paint()..color = kInk);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => true;
}
