import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import 'stat_card.dart';

/// Share of plays per genre: the six largest as labelled bars.
class GenreMixCard extends StatelessWidget {
  final List<Map<String, dynamic>> genres;
  const GenreMixCard({super.key, required this.genres});

  static double _pct(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final top = genres.where((g) => _pct(g['pct']) > 0).take(6).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final max = _pct(top.first['pct']);

    return StatCard(
      title: 'Genres',
      child: Column(
        children: [
          for (final g in top)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm + 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      g['genre']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.footnote.copyWith(color: t.textPrimary),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(height: 6, color: t.fill),
                          FractionallySizedBox(
                            widthFactor: max == 0 ? 0 : _pct(g['pct']) / max,
                            child: Container(height: 6, color: t.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_pct(g['pct']).round()}%',
                      textAlign: TextAlign.right,
                      style: t.footnote.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
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
