import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import 'stat_card.dart';

/// Share of plays per genre as a typographic ladder: each genre is set in
/// type sized by its share, so the shape of your taste reads as a silhouette
/// of words (one big, a few medium, a tail) rather than as bars.
class GenreMixCard extends StatelessWidget {
  static const _shown = 5;
  static const double _big = 40;
  static const double _small = 17;

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
    final peak = parts.first.$2;

    return StatSection(
      title: 'Genres',
      child: Semantics(
        label: 'Genres: ${[for (final p in parts) '${p.$1} ${p.$2.round()} percent'].join(', ')}',
        excludeSemantics: true,
        child: Column(
          children: [
            for (final (i, p) in parts.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        p.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t
                            .textStyle(
                              (_small + (_big - _small) * (peak == 0 ? 0 : p.$2 / peak)).roundToDouble(),
                              FontWeight.w700,
                              i == 0 ? t.gold : (i == parts.length - 1 && other > 0 ? t.textMuted : t.textSecondary),
                            )
                            .copyWith(height: 1.1, letterSpacing: -0.6),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Text('${p.$2.round()}%', style: figureStyle(t, 15).copyWith(color: t.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
