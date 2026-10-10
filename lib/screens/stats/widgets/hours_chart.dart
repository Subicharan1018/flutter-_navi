import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// Plays by hour of day as 24 bars. The card leads with the peak hour; tap a
/// bar to read that hour instead.
class HoursChart extends StatefulWidget {
  final Map<String, int> byHour;
  const HoursChart({super.key, required this.byHour});

  @override
  State<HoursChart> createState() => _HoursChartState();
}

class _HoursChartState extends State<HoursChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    int count(int h) => widget.byHour['$h'] ?? 0;
    final max = List.generate(24, count).fold(0, (a, b) => a > b ? a : b);
    if (max == 0) return const SizedBox.shrink();
    final peak = List.generate(24, (h) => h).firstWhere((h) => count(h) == max);
    final shown = _selected ?? peak;

    return StatCard(
      title: 'Listening Hours',
      readout: hourLabel(shown),
      readoutColor: t.accent,
      readoutCaption: _selected == null
          ? 'is when you listen most'
          : (count(shown) == 1 ? '1 play' : '${count(shown)} plays'),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var h = 0; h < 24; h++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = _selected == h ? null : h);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.standard,
                        curve: Motion.ease,
                        height: 4 + 84 * count(h) / max,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: h == shown ? t.accent : t.accentDim,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        height: 13,
                        child: h % 6 == 0
                            ? OverflowBox(
                                maxWidth: 40,
                                child: Text(hourLabel(h, compact: true), maxLines: 1, style: t.caption2),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
