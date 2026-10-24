import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// Plays by hour of day drawn as what they are: a 24-hour clock. Midnight
/// sits at the top, noon at the bottom, and each hour is a bar growing out
/// from the ring. The centre reads the busiest hour; tap an hour to read
/// it, or press and hold and sweep around the dial (iOS's chart-scrub
/// gesture, so a quick swipe still scrolls the page), with a tick of
/// haptics per hour.
class ListeningClock extends StatefulWidget {
  final Map<String, int> byHour;
  const ListeningClock({super.key, required this.byHour});

  @override
  State<ListeningClock> createState() => _ListeningClockState();
}

class _ListeningClockState extends State<ListeningClock> {
  static const double _maxDial = 320;

  /// Hold this long before a drag scrubs instead of scrolling.
  static const Duration _scrubHold = Duration(milliseconds: 180);
  int? _selected;

  int _count(int h) => widget.byHour['$h'] ?? 0;

  static String _spoken(int h, List<int> counts) =>
      '${hourLabel(h)}, ${counts[h] == 1 ? '1 play' : '${counts[h]} plays'}';

  /// The hour under [local] on a dial of [size], or null in the hub.
  int? _hourAt(Offset local, double size) {
    final v = local - Offset(size / 2, size / 2);
    if (v.distance < _ClockGeometry(size).hub) return null;
    // 0 rad at 12 o'clock, clockwise.
    final angle = (math.atan2(v.dx, -v.dy) + 2 * math.pi) % (2 * math.pi);
    return (angle / (2 * math.pi) * 24).round() % 24;
  }

  void _select(int? h) {
    if (h == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = h);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final counts = List.generate(24, _count);
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    if (max == 0) return const SizedBox.shrink();
    final peak = counts.indexOf(max);
    final shown = _selected ?? peak;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return StatSection(
      title: 'Listening Hours',
      child: LayoutBuilder(builder: (context, c) {
        final size = math.min(c.maxWidth, _maxDial);
        final geometry = _ClockGeometry(size);
        return Center(
          child: Semantics(
            label: 'Listening by hour',
            value: _spoken(shown, counts),
            increasedValue: _spoken((shown + 1) % 24, counts),
            decreasedValue: _spoken((shown + 23) % 24, counts),
            onIncrease: () => _select((shown + 1) % 24),
            onDecrease: () => _select((shown + 23) % 24),
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(duration: _scrubHold),
                  (r) {
                    r
                      ..onLongPressStart = ((d) => _select(_hourAt(d.localPosition, size) ?? shown))
                      ..onLongPressMoveUpdate = ((d) => _select(_hourAt(d.localPosition, size) ?? shown));
                  },
                ),
                TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  // A tap in the hub returns to the busiest hour.
                  (r) => r.onTapUp = (d) => _select(_hourAt(d.localPosition, size)),
                ),
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduce ? 1 : 0, end: 1),
                duration: Motion.slow * 3,
                curve: Curves.easeOutExpo,
                builder: (context, grow, _) => SizedBox.square(
                  dimension: size,
                  child: CustomPaint(
                    painter: _ClockPainter(
                      geometry: geometry,
                      counts: counts,
                      max: max,
                      selected: shown,
                      grow: grow,
                      on: t.accent,
                      dim: t.accentDim,
                      empty: t.fill,
                      ring: t.outline,
                      labelStyle: t.caption2,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: geometry.hub * 2 - Space.lg,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(hourLabel(shown), style: figureStyle(t, size * 0.11).copyWith(color: t.accent)),
                            ),
                            const SizedBox(height: Space.xxs),
                            Text(
                              _selected == null
                                  ? 'busiest hour'
                                  : (counts[shown] == 1 ? '1 play' : '${counts[shown]} plays'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: t.footnote,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// The dial's radii, shared by painting and hit-testing so they never drift.
class _ClockGeometry {
  /// Room around the bars for the quarter labels.
  static const double labelBand = 18;

  final double size;
  const _ClockGeometry(this.size);

  double get centre => size / 2;

  /// Where bars may reach.
  double get outer => centre - labelBand;

  /// Where bars start.
  double get inner => outer * 0.5;

  /// The readout's room in the middle.
  double get hub => inner - 6;
}

class _ClockPainter extends CustomPainter {
  final _ClockGeometry geometry;
  final List<int> counts;
  final int max;
  final int selected;

  /// 0→1 on first appearance: bars grow out from the ring, in hour order.
  final double grow;
  final Color on;
  final Color dim;
  final Color empty;
  final Color ring;
  final TextStyle labelStyle;

  _ClockPainter({
    required this.geometry,
    required this.counts,
    required this.max,
    required this.selected,
    required this.grow,
    required this.on,
    required this.dim,
    required this.empty,
    required this.ring,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final inner = geometry.inner;
    final reach = geometry.outer - inner - 2;
    final bar = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (2 * math.pi * inner / 24) * 0.5;
    final base = inner + bar.strokeWidth / 2;

    // Hairline ring the bars stand on.
    canvas.drawCircle(
      c,
      geometry.hub,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = ring,
    );

    for (var h = 0; h < 24; h++) {
      // Each hour starts growing a little after the one before it.
      final local = ((grow * 1.6) - h / 24 * 0.6).clamp(0.0, 1.0);
      final length = counts[h] == 0 ? 2.0 : 6 + (reach - bar.strokeWidth - 6) * counts[h] / max * local;
      final a = h / 24 * 2 * math.pi;
      final dir = Offset(math.sin(a), -math.cos(a));
      bar.color = counts[h] == 0 ? empty : (h == selected ? on : dim);
      canvas.drawLine(c + dir * base, c + dir * (base + length), bar);
    }

    // Quarter labels just outside the bar tips, like a clock face.
    for (final (h, label) in const [(0, '12a'), (6, '6a'), (12, '12p'), (18, '6p')]) {
      final a = h / 24 * 2 * math.pi;
      final p = c + Offset(math.sin(a), -math.cos(a)) * (geometry.centre - _ClockGeometry.labelBand / 2);
      final tp = TextPainter(text: TextSpan(text: label, style: labelStyle), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.selected != selected || old.grow != grow || old.max != max || old.on != on || old.counts != counts;
}
