import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../utils/platform_utils.dart';
import '../logic/eq_model.dart';

/// "+3.5 dB", "0 dB", "-12 dB".
String formatDb(double db) {
  final s = db.abs() < 0.05 ? '0' : db.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '${db >= 0.05 ? '+' : ''}$s dB';
}

const double _axisWidth = 52;
const double _plotHeight = 240;
const double _pad = 22; // room for a handle and its value above +12 dB

/// The six-band curve. Drag a point (or anywhere in its column) up and down.
///
/// Keyboard: left and right move between bands, up and down change the gain.
/// On a TV the arrows must also be able to leave the curve, so Select starts
/// and ends changing a band.
class EqCurve extends StatefulWidget {
  final List<double> gains;
  final bool enabled;
  final void Function(int band, double db) onChanged;
  final VoidCallback onChangeEnd;

  const EqCurve({
    super.key,
    required this.gains,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<EqCurve> createState() => _EqCurveState();
}

class _EqCurveState extends State<EqCurve> {
  late final List<FocusNode> _nodes = [
    for (final label in kEqFrequencyLabels) FocusNode(debugLabel: 'eq-$label'),
  ];
  int? _dragging;
  int? _focused;
  bool _editing = false;

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  static double _dbAt(double y) {
    final span = _plotHeight - _pad * 2;
    final db = kEqMaxDb - (y - _pad) / span * kEqMaxDb * 2;
    // A small catch at zero, so "no change" is easy to hit with a finger.
    return db.abs() < 0.6 ? 0 : (db * 2).round() / 2;
  }

  void _set(int band, double db) {
    final next = db.clamp(-kEqMaxDb, kEqMaxDb).toDouble();
    if ((next - widget.gains[band]).abs() < 0.05) return;
    if (next == 0) HapticFeedback.selectionClick();
    widget.onChanged(band, next);
  }

  void _endDrag() {
    if (_dragging == null) return;
    setState(() => _dragging = null);
    widget.onChangeEnd();
  }

  KeyEventResult _onKey(int band, KeyEvent event) {
    if (event is KeyUpEvent || !widget.enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final select = key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    if (PlatformUtils.isTv) {
      if (select) {
        if (event is KeyDownEvent) setState(() => _editing = !_editing);
        return KeyEventResult.handled;
      }
      if (!_editing) return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _set(band, widget.gains[band] + (key == LogicalKeyboardKey.arrowUp ? 1 : -1));
      widget.onChangeEnd();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && band > 0) {
      _nodes[band - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && band < _nodes.length - 1) {
      _nodes[band + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final active = widget.enabled ? (_dragging ?? _focused) : null;
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: widget.enabled ? 1 : 0.38,
      child: Column(
        children: [
          SizedBox(
            height: _plotHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _axisWidth,
                  child: Stack(
                    children: [
                      Positioned(top: _pad - 8, left: 0, child: Text('+12dB', style: t.footnote)),
                      Positioned(bottom: _pad - 8, left: 0, child: Text('-12dB', style: t.footnote)),
                    ],
                  ),
                ),
                Expanded(child: LayoutBuilder(builder: (context, box) => _plot(t, box.maxWidth, active))),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          ExcludeSemantics(
            child: Row(
              children: [
                const SizedBox(width: _axisWidth),
                for (var i = 0; i < kEqFrequencyLabels.length; i++)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        kEqFrequencyLabels[i],
                        style: t.footnote.copyWith(
                          fontWeight: FontWeight.w600,
                          color: i == active ? t.textPrimary : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plot(AppThemeTokens t, double width, int? active) {
    final column = width / kEqFrequencies.length;
    int bandAt(double x) => (x / column).floor().clamp(0, kEqFrequencies.length - 1);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragDown: widget.enabled ? (d) => _dragging = bandAt(d.localPosition.dx) : null,
      onVerticalDragStart: widget.enabled
          ? (d) {
              setState(() {});
              _set(_dragging!, _dbAt(d.localPosition.dy));
            }
          : null,
      onVerticalDragUpdate: widget.enabled ? (d) => _set(_dragging!, _dbAt(d.localPosition.dy)) : null,
      onVerticalDragEnd: widget.enabled ? (_) => _endDrag() : null,
      onVerticalDragCancel: widget.enabled ? _endDrag : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _CurvePainter(
                gains: widget.gains,
                line: t.accent,
                grid: t.outline,
                ground: t.bgBase,
                label: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700),
                active: active,
                ring: _focused != null,
                editing: _editing,
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < kEqFrequencies.length; i++)
                Expanded(
                  child: Semantics(
                    slider: true,
                    enabled: widget.enabled,
                    label: kEqFrequencyLabels[i],
                    value: formatDb(widget.gains[i]),
                    increasedValue: formatDb((widget.gains[i] + 1).clamp(-kEqMaxDb, kEqMaxDb)),
                    decreasedValue: formatDb((widget.gains[i] - 1).clamp(-kEqMaxDb, kEqMaxDb)),
                    onIncrease: widget.enabled
                        ? () {
                            _set(i, widget.gains[i] + 1);
                            widget.onChangeEnd();
                          }
                        : null,
                    onDecrease: widget.enabled
                        ? () {
                            _set(i, widget.gains[i] - 1);
                            widget.onChangeEnd();
                          }
                        : null,
                    child: Focus(
                      focusNode: _nodes[i],
                      canRequestFocus: widget.enabled,
                      onKeyEvent: (_, e) => _onKey(i, e),
                      onFocusChange: (has) => setState(() {
                        if (has) {
                          _focused = i;
                        } else if (_focused == i) {
                          _focused = null;
                          _editing = false;
                        }
                      }),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<double> gains;
  final Color line, grid, ground;
  final TextStyle label;
  final int? active;
  final bool ring, editing;

  _CurvePainter({
    required this.gains,
    required this.line,
    required this.grid,
    required this.ground,
    required this.label,
    required this.active,
    required this.ring,
    required this.editing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final column = size.width / gains.length;
    double x(num band) => column * (band + 0.5);
    double y(double db) => _pad + (kEqMaxDb - db) / (kEqMaxDb * 2) * (size.height - _pad * 2);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < gains.length; i++) {
      canvas.drawLine(Offset(x(i), _pad), Offset(x(i), size.height - _pad), gridPaint);
    }
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), gridPaint);

    final positions = [for (var i = 0; i < gains.length; i++) i.toDouble()];
    const steps = 20;
    final curve = Path();
    for (var s = 0; s <= (gains.length - 1) * steps; s++) {
      final at = s / steps;
      final p = Offset(x(at), y(curveAt(positions, gains, at)));
      s == 0 ? curve.moveTo(p.dx, p.dy) : curve.lineTo(p.dx, p.dy);
    }
    final area = Path.from(curve)
      ..lineTo(x(gains.length - 1), size.height - _pad)
      ..lineTo(x(0), size.height - _pad)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.22), line.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTRB(0, _pad, size.width, size.height - _pad)),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < gains.length; i++) {
      final c = Offset(x(i), y(gains[i]));
      final isActive = i == active;
      if (isActive && ring) {
        canvas.drawCircle(
          c,
          editing ? 16 : 14,
          Paint()
            ..color = line.withValues(alpha: editing ? 1 : 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = editing ? 3 : 2,
        );
      }
      // A ground-coloured collar keeps the white handle apart from the line.
      canvas.drawCircle(c, isActive ? 11 : 9.5, Paint()..color = ground);
      canvas.drawCircle(c, isActive ? 8 : 6.5, Paint()..color = line);
      if (isActive) {
        final text = TextPainter(
          text: TextSpan(text: formatDb(gains[i]), style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        final above = c.dy - 20 - text.height;
        text.paint(
          canvas,
          Offset(
            (c.dx - text.width / 2).clamp(0, size.width - text.width).toDouble(),
            above >= 0 ? above : c.dy + 18,
          ),
        );
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      !sameGains(old.gains, gains) ||
      old.active != active ||
      old.ring != ring ||
      old.editing != editing ||
      old.line != line ||
      old.grid != grid ||
      old.ground != ground;
}
