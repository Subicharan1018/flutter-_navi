import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// A year of listening, one square per day, painted in a single layer.
/// Tap a day to read it; the grid opens scrolled to this week.
class YearGrid extends StatefulWidget {
  final List<ContributionDay> days;
  const YearGrid({super.key, required this.days});

  @override
  State<YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<YearGrid> {
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _step = _cell + _gap;
  static const _dayLabelWidth = 18.0;
  static const _monthLabelHeight = 18.0;
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  final _scroll = ScrollController();
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final byDate = {for (final d in widget.days) d.date: d.count};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Columns are Sunday-first weeks; the last column holds today.
    final start = today.subtract(Duration(days: 364 + today.weekday % 7));
    final weeks = (today.difference(start).inDays ~/ 7) + 1;
    final total = widget.days.fold<int>(0, (s, d) => s + d.count);
    final active = widget.days.where((d) => d.count > 0).length;

    int countOn(DateTime d) => byDate[isoDate(d)] ?? 0;
    final selectedCount = _selected == null ? 0 : countOn(_selected!);

    return StatSection(
      title: 'Your Year',
      readout: _selected == null ? '$active days' : '${_months[_selected!.month - 1]} ${_selected!.day}',
      readoutCaption: _selected == null
          ? 'with music, ${compactCount(total)} plays in all'
          : (selectedCount == 1 ? '1 play' : '$selectedCount plays'),
      readoutColor: _selected == null ? null : t.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              onTapUp: (e) {
                final w = ((e.localPosition.dx - _dayLabelWidth) / _step).floor();
                final d = ((e.localPosition.dy - _monthLabelHeight) / _step).floor();
                if (w < 0 || w >= weeks || d < 0 || d > 6) return;
                final day = start.add(Duration(days: w * 7 + d));
                if (day.isAfter(today)) return;
                HapticFeedback.selectionClick();
                setState(() => _selected = _selected == day ? null : day);
              },
              child: CustomPaint(
                size: Size(_dayLabelWidth + weeks * _step, _monthLabelHeight + 7 * _step),
                painter: _GridPainter(
                  start: start,
                  today: today,
                  weeks: weeks,
                  countOn: countOn,
                  selected: _selected,
                  empty: t.fill,
                  accent: t.accent,
                  outline: t.textPrimary,
                  label: t.caption2,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less', style: t.caption2),
              const SizedBox(width: Space.xs + 2),
              for (final level in _GridPainter.levels)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: _GridPainter.shade(level, t.fill, t.accent),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: Space.xs),
              Text('More', style: t.caption2),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  /// Fill strength for 0, 1–3, 4–8, 9–17 and 18+ plays.
  static const levels = [0.0, 0.3, 0.55, 0.8, 1.0];

  final DateTime start;
  final DateTime today;
  final int weeks;
  final int Function(DateTime) countOn;
  final DateTime? selected;
  final Color empty;
  final Color accent;
  final Color outline;
  final TextStyle label;

  _GridPainter({
    required this.start,
    required this.today,
    required this.weeks,
    required this.countOn,
    required this.selected,
    required this.empty,
    required this.accent,
    required this.outline,
    required this.label,
  });

  static double _level(int c) => c == 0 ? 0 : c < 4 ? levels[1] : c < 9 ? levels[2] : c < 18 ? levels[3] : levels[4];

  /// Solid step between the empty cell and full accent (no transparency).
  static Color shade(double level, Color empty, Color accent) => Color.lerp(empty, accent, level)!;

  /// Paints [s] at [at] unless it would be clipped by [maxX] (a month label
  /// in the last column).
  void _text(Canvas canvas, String s, Offset at, {double maxX = double.infinity}) {
    final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: TextDirection.ltr)..layout();
    if (at.dx + tp.width <= maxX) tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const step = _YearGridState._step;
    const cell = _YearGridState._cell;
    const left = _YearGridState._dayLabelWidth;
    const top = _YearGridState._monthLabelHeight;
    final paint = Paint();

    for (final (row, letter) in const [(1, 'M'), (3, 'W'), (5, 'F')]) {
      _text(canvas, letter, Offset(0, top + row * step - 1));
    }

    int? lastMonth;
    for (var w = 0; w < weeks; w++) {
      final weekStart = start.add(Duration(days: w * 7));
      if (weekStart.month != lastMonth) {
        lastMonth = weekStart.month;
        _text(canvas, _YearGridState._months[weekStart.month - 1], Offset(left + w * step, 0), maxX: size.width);
      }
      for (var d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        if (day.isAfter(today)) continue;
        final level = _level(countOn(day));
        paint.color = shade(level, empty, accent);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left + w * step, top + d * step, cell, cell),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(rect, paint);
        if (day == selected) {
          canvas.drawRRect(
            rect.inflate(1.5),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = outline,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.selected != selected || old.weeks != weeks || old.accent != accent || old.countOn != countOn;
}
