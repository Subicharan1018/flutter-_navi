import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';
import 'stat_card.dart' show figureStyle;

class RankedBarItem {
  final String label;
  final String? detail;
  final double value;

  /// Cover, portrait or generated art shown before the label.
  final Widget? leading;
  const RankedBarItem({required this.label, required this.value, this.detail, this.leading});
}

/// Names ranked by a bar that grows from the left, one after another, to its
/// share of the leader. The leader's bar takes the accent; the rest are quiet.
class RankedBarList extends StatelessWidget {
  final List<RankedBarItem> items;
  final Animation<double>? progress;

  const RankedBarList({super.key, required this.items, this.progress});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final peak = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    return PlayOnce(
      progress: progress,
      duration: Duration(milliseconds: 700 + 120 * items.length),
      curve: Curves.linear,
      builder: (context, p) => AnimatedBuilder(
        animation: p,
        builder: (context, _) {
          final n = items.length;
          return Column(
            children: [
              for (final (i, item) in items.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
                  child: _Row(
                    rank: i + 1,
                    item: item,
                    share: peak == 0 ? 0 : item.value / peak,
                    // Each row owns a staggered slice of the one clock.
                    grow: sliceOf(p.value, i / (n + 1), (i + 2) / (n + 1), Curves.easeOutCubic),
                    lead: i == 0,
                    t: t,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final int rank;
  final RankedBarItem item;
  final double share;
  final double grow;
  final bool lead;
  final AppThemeTokens t;
  const _Row({required this.rank, required this.item, required this.share, required this.grow, required this.lead, required this.t});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rank. ${item.label}${item.detail == null ? '' : ', ${item.detail}'}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank', style: figureStyle(t, 15).copyWith(color: lead ? t.accent : t.textSecondary))),
          if (item.leading != null) ...[item.leading!, const SizedBox(width: Space.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body)),
                    if (item.detail != null) Text(item.detail!, style: t.footnote),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: t.fill)),
                        FractionallySizedBox(
                          widthFactor: (share * grow).clamp(0.0, 1.0),
                          child: ColoredBox(color: lead ? t.accent : t.textSecondary),
                        ),
                      ],
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
}
