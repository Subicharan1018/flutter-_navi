import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/contribution_graph_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// The last two weeks, day by day: tall bars sized by plays, today lit on
/// the right, each day's count above its bar. The section leads with the
/// fortnight's total; tap a day to read that day instead.
class FortnightChart extends StatefulWidget {
  final List<ContributionDay> days;
  const FortnightChart({super.key, required this.days});

  @override
  State<FortnightChart> createState() => _FortnightChartState();
}

class _FortnightChartState extends State<FortnightChart> {
  static const int _window = 14;
  static const double _barArea = 168;
  static const double _countRow = 18;
  static const double _minBar = 6;
  static const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  int? _selected;

  void _select(int i) {
    HapticFeedback.selectionClick();
    setState(() => _selected = _selected == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final byDate = {for (final d in widget.days) d.date: d.count};
    final now = DateTime.now();
    final dates = [for (var i = 0; i < _window; i++) now.subtract(Duration(days: _window - 1 - i))];
    final counts = [for (final d in dates) byDate[isoDate(d)] ?? 0];
    final total = counts.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    final active = counts.where((c) => c > 0).length;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final selected = _selected;
    final readout = selected == null ? compactCount(total) : '${counts[selected]}';
    final caption = selected == null
        ? 'plays across $active of the last 14 days'
        : '${counts[selected] == 1 ? 'play' : 'plays'} on '
            '${_weekdays[dates[selected].weekday - 1]} ${dates[selected].day} ${_months[dates[selected].month - 1]}';

    return StatSection(
      title: 'Last 2 Weeks',
      readout: readout,
      readoutCaption: caption,
      readoutColor: t.accent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: Motion.slow * 2,
        curve: Curves.easeOutExpo,
        builder: (context, grow, _) => Column(
          children: [
            SizedBox(
              height: _barArea + _countRow,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _window; i++) ...[
                    if (i > 0) const SizedBox(width: Space.xs),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '${_weekdays[dates[i].weekday - 1]} ${dates[i].day}, ${counts[i]} plays',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _select(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: _countRow,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    counts[i] == 0 ? '' : '${counts[i]}',
                                    style: t.caption2.copyWith(
                                      color: i == selected || (selected == null && i == _window - 1)
                                          ? t.textPrimary
                                          : t.textMuted,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                height: counts[i] == 0
                                    ? _minBar
                                    : _minBar + (_barArea - _minBar) * counts[i] / max * grow,
                                decoration: BoxDecoration(
                                  color: _barColor(t, i, counts[i], selected),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (var i = 0; i < _window; i++) ...[
                  if (i > 0) const SizedBox(width: Space.xs),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _weekdays[dates[i].weekday - 1].substring(0, 1),
                          style: t.caption2.copyWith(
                            color: i == _window - 1 ? t.textPrimary : t.textMuted,
                          ),
                        ),
                        Text(
                          '${dates[i].day}',
                          style: t.caption2.copyWith(
                            color: i == _window - 1 ? t.accent : t.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Today and the tapped day are full green; the rest a deeper green;
  /// a day with no music is a stub in the fill colour.
  static Color _barColor(AppThemeTokens t, int i, int count, int? selected) {
    if (count == 0) return t.fill;
    final lit = selected == null ? i == _window - 1 : i == selected;
    return lit ? t.accent : t.accentDim;
  }
}
