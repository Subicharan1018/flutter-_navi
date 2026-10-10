import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import 'stat_card.dart';

/// Share of plays per genre as one bar split by genre (the shape of your
/// taste at a glance), then a legend with the numbers. Shades step from the
/// accent toward the page, so the biggest genre is the brightest.
class GenreMixCard extends StatelessWidget {
  static const _shown = 5;

  final List<Map<String, dynamic>> genres;
  const GenreMixCard({super.key, required this.genres});

  static double _pct(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final ranked = genres.where((g) => _pct(g['pct']) > 0).toList();
    if (ranked.isEmpty) return const SizedBox.shrink();
    final top = ranked.take(_shown).toList();
    final other = ranked.skip(_shown).fold<double>(0, (s, g) => s + _pct(g['pct']));
    final parts = [
      for (final g in top) (g['genre']?.toString() ?? 'Unknown', _pct(g['pct'])),
      if (other > 0) ('Everything else', other),
    ];
    Color shade(int i) => i == parts.length - 1 && other > 0
        ? t.fill
        : Color.lerp(t.accent, t.bgOverlay, i / _shown)!;

    return StatSection(
      title: 'Genres',
      readout: parts.first.$1,
      readoutCaption: 'leads with ${parts.first.$2.round()}% of your plays',
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, p) in parts.indexed) ...[
                    if (i > 0) SizedBox(width: 2, child: ColoredBox(color: t.bgBase)),
                    Expanded(flex: (p.$2 * 10).round().clamp(1, 1000), child: ColoredBox(color: shade(i))),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          for (final (i, p) in parts.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm + 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: shade(i), borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: Space.sm + 2),
                  Expanded(
                    child: Text(p.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout),
                  ),
                  Text(
                    '${p.$2.round()}%',
                    style: t.callout.copyWith(
                      color: t.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
