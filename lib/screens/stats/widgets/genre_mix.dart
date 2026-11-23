import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/motion/play_once.dart';
import 'stat_card.dart';

/// Genres as a typographic poster: a white sheet, the leading genre set so
/// large it fills the width in black, the rest stepping down in size by their
/// share like the credits on a film poster. The words are the chart. Lines
/// slide up one after another once.
class GenreMixCard extends StatelessWidget {
  static const _shown = 5;
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ColoredBox(
            color: t.accent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
              child: PlayOnce(
                duration: const Duration(milliseconds: 1100),
                curve: Curves.linear,
                builder: (context, p) => AnimatedBuilder(
                  animation: p,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, g) in parts.indexed)
                        _Line(
                          // Each line owns a slice of the one clock.
                          k: Curves.easeOutCubic.transform(((p.value - i * 0.12) / 0.5).clamp(0.0, 1.0)),
                          child: i == 0
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    g.$1,
                                    maxLines: 1,
                                    style: t
                                        .textStyle(76, FontWeight.w800, t.onAccent)
                                        .copyWith(height: 1.0, letterSpacing: -3),
                                  ),
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        g.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t
                                            .textStyle(
                                              (_small + 17 * (g.$2 / peak)).roundToDouble(),
                                              FontWeight.w700,
                                              t.onAccent.withValues(alpha: i == parts.length - 1 && other > 0 ? 0.45 : 0.85),
                                            )
                                            .copyWith(height: 1.15, letterSpacing: -0.5),
                                      ),
                                    ),
                                    Text('${g.$2.round()}%', style: figureStyle(t, 15).copyWith(color: t.onAccent.withValues(alpha: 0.6))),
                                  ],
                                ),
                        ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'LEADS WITH ${parts.first.$2.round()}% OF YOUR PLAYS',
                        style: t.caption2.copyWith(color: t.onAccent.withValues(alpha: 0.55), letterSpacing: 1.1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final double k;
  final Widget child;
  const _Line({required this.k, required this.child});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: k,
    child: Transform.translate(offset: Offset(0, 14 * (1 - k)), child: child),
  );
}
