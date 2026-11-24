import 'package:flutter/cupertino.dart';

import '../../../core/theme.dart';
import 'wrapped_screen.dart';

const wInk = Color(0xFFFFFFFF);
const wGround = Color(0xFF000000);

/// The year Wrapped is on offer for: this year from 1 October, and last year through January.
/// Null the rest of the year (Stats still opens it).
int? wrappedYearFor(DateTime now) {
  if (now.month >= 10) return now.year;
  if (now.month == 1) return now.year - 1;
  return null;
}

/// The Home card's picture: the year set big on a black square, with a row of bars.
class WrappedCardArt extends StatelessWidget {
  final int year;
  final double size;
  const WrappedCardArt({super.key, required this.year, required this.size});

  static const _bars = [0.35, 0.6, 0.45, 0.9, 0.55, 0.75, 0.4, 1.0, 0.65, 0.5];

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: size,
      height: size,
      color: wGround,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _bars.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: _bars[i] * 0.8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: i == 7 ? wInk : const Color(0xFF3A3A3C), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Text('Wrapped', style: t.title3.copyWith(color: wInk)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$year',
              style: t.largeTitle.copyWith(color: wInk, fontSize: size * 0.3, height: 1, letterSpacing: -2),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet row for Stats: the year as a story, with a Play capsule. No box around it.
class WrappedStatsRow extends StatelessWidget {
  final int year;
  const WrappedStatsRow({super.key, required this.year});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: () => showWrapped(context, year: year),
      semanticLabel: 'Play Wrapped $year',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wrapped $year', style: t.title2),
                  const SizedBox(height: 2),
                  Text('Your year in music, played as a story you can share.', style: t.footnote.copyWith(color: t.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.accentFill, borderRadius: BorderRadius.circular(Radii.capsule)),
              child: Text('Play', style: t.headline.copyWith(color: t.onAccent)),
            ),
          ],
        ),
      ),
    );
  }
}
