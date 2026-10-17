import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../data/trending_models.dart';
import 'chart_details.dart';
import 'chart_row.dart';

/// A Trending page row, like billboard.com's: a row with details opens on
/// tap to show them (with Play); one without plays straight away. The open
/// state lives here, so only this row rebuilds.
class ExpandableChartRow extends StatefulWidget {
  final ChartEntry entry;
  final VoidCallback onPlay;
  final bool showSeparator;

  const ExpandableChartRow({super.key, required this.entry, required this.onPlay, this.showSeparator = true});

  @override
  State<ExpandableChartRow> createState() => _ExpandableChartRowState();
}

class _ExpandableChartRowState extends State<ExpandableChartRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final e = widget.entry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChartRow(
          entry: e,
          detailed: true,
          expanded: _open,
          showSeparator: widget.showSeparator,
          onTap: e.hasDetails
              ? () {
                  HapticFeedback.selectionClick();
                  setState(() => _open = !_open);
                }
              : widget.onPlay,
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: widget.showSeparator
                        ? Border(bottom: BorderSide(color: t.outline, width: 0.5))
                        : null,
                  ),
                  child: ChartDetailsPanel(entry: e, onPlay: widget.onPlay),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
