import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import 'taste_math.dart';

/// "Why these songs": the picks as dots around the moment. Nearer the centre =
/// a closer fit (or, while the energy dial is held, closer to the dial). The
/// dots drift slowly like a small orbit and glide to new places with a
/// critically-damped spring when the mix or the dial changes. A new mix blooms
/// out of the centre. Under reduced motion it is the same picture, still.
class TasteField extends StatefulWidget {
  final List<TastePoint> points;
  final double? dial;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final double height;

  const TasteField({
    super.key,
    required this.points,
    required this.dial,
    required this.selectedId,
    required this.onSelect,
    this.height = 280,
  });

  @override
  State<TasteField> createState() => _TasteFieldState();
}

class _TasteFieldState extends State<TasteField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);

  final Map<String, double> _radius = {}; // current, glides to target
  final Map<String, double> _target = {};
  final Map<String, double> _angle = {};
  final Map<String, double> _bornAt = {}; // clock time a dot starts blooming
  final Map<String, double> _speed = {};
  double _clock = 0;
  double _orbit = 0;
  Duration _last = Duration.zero;
  bool _reduce = false;

  static const double _bloomSeconds = 0.6;

  @override
  void initState() {
    super.initState();
    _retarget(initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce) {
      _ticker.stop();
      _radius.addAll(_target);
      _repaint.value++;
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(TasteField old) {
    super.didUpdateWidget(old);
    _retarget();
    if (_reduce) {
      _radius.addAll(_target);
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _retarget({bool initial = false}) {
    final pts = widget.points;
    final radii = tasteRadii(pts, dial: widget.dial);
    final ids = {for (final p in pts) p.id};
    for (final k in _target.keys.where((k) => !ids.contains(k)).toList()) {
      _target.remove(k);
      _radius.remove(k);
      _angle.remove(k);
      _bornAt.remove(k);
      _speed.remove(k);
    }
    var fresh = 0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      _target[p.id] = radii[p.id]!;
      _angle[p.id] = tasteAngle(p, i);
      if (!_radius.containsKey(p.id)) {
        // A new pick blooms from the centre, staggered by 45 ms.
        _radius[p.id] = 0;
        _bornAt[p.id] = (initial ? 0.15 : _clock) + fresh * 0.045;
        _speed[p.id] = 0.5 + ((i * 0.37) % 1.0);
        fresh++;
      }
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _clock += dt;
    _orbit += dt * 0.045;
    final k = 1 - math.exp(-dt * 8); // critically damped glide
    _radius.forEach((id, r) {
      if (_clock < (_bornAt[id] ?? 0)) return;
      _radius[id] = r + (_target[id]! - r) * k;
    });
    _repaint.value++;
  }

  double _bloom(String id) {
    if (_reduce) return 1;
    final t = (_clock - (_bornAt[id] ?? 0)) / _bloomSeconds;
    return Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  }

  Offset _pos(String id, Size size) {
    final side = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final r = (_radius[id] ?? 0) * (side / 2 - 10);
    final a = (_angle[id] ?? 0) + (_reduce ? 0 : _orbit * (_speed[id] ?? 1) / math.max(0.25, (_radius[id] ?? 0.5) + 0.35));
    return c + Offset(math.cos(a), math.sin(a)) * r;
  }

  void _tap(Offset local, Size size) {
    String? best;
    var bestD = 28.0; // a fingertip
    for (final p in widget.points) {
      final d = (_pos(p.id, size) - local).distance;
      if (d < bestD) {
        bestD = d;
        best = p.id;
      }
    }
    if (best != widget.selectedId) HapticFeedback.selectionClick();
    widget.onSelect(best == widget.selectedId ? null : best);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      label: 'Taste field. ${widget.points.length} picks; the nearer the centre, the closer the fit.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, widget.height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition, size),
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _FieldPainter(
                  repaint: _repaint,
                  state: this,
                  ink: t.textPrimary,
                  faint: t.textMuted,
                  selectedId: widget.selectedId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  final _TasteFieldState state;
  final Color ink;
  final Color faint;
  final String? selectedId;

  _FieldPainter({required Listenable repaint, required this.state, required this.ink, required this.faint, required this.selectedId})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final R = side / 2 - 10;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = faint.withValues(alpha: 0.28);
    for (final f in const [0.33, 0.66, 1.0]) {
      canvas.drawCircle(c, R * f, ring);
    }

    // The selected pick is tied to the centre by a hairline.
    final sel = selectedId;
    if (sel != null && state._radius.containsKey(sel)) {
      canvas.drawLine(c, state._pos(sel, size), Paint()
        ..color = ink.withValues(alpha: 0.55)
        ..strokeWidth = 1);
    }

    final dot = Paint()..style = PaintingStyle.fill;
    for (final p in state.widget.points) {
      final b = state._bloom(p.id);
      if (b <= 0) continue;
      final pos = state._pos(p.id, size);
      final r = 3.6 + p.dance * 4.0;
      final isSel = p.id == sel;
      dot.color = ink.withValues(alpha: (isSel ? 1.0 : 0.82) * b);
      canvas.drawCircle(pos, r * (0.4 + 0.6 * b), dot);
      if (isSel) {
        canvas.drawCircle(
            pos,
            r + 5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = ink);
      }
    }

    // The moment itself: a solid centre inside a thin ring.
    canvas.drawCircle(c, 9, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: 0.5));
    canvas.drawCircle(c, 4.5, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.ink != ink || old.faint != faint || old.selectedId != selectedId;
}
