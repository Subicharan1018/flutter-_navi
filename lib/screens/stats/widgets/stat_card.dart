import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';

/// Apple Health-style card: a title, the card's one-line answer under it,
/// then the chart or list that backs it up.
class StatCard extends StatelessWidget {
  final String title;

  /// The headline answer, e.g. "9 pm" or "Up 12%". Shown large, in [readoutColor].
  final String? readout;
  final String? readoutCaption;
  final Color? readoutColor;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const StatCard({
    super.key,
    required this.title,
    this.readout,
    this.readoutCaption,
    this.readoutColor,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.group)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: t.headline)),
          if (readout != null) ...[
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(readout!, style: figureStyle(t, 28).copyWith(color: readoutColor ?? t.textPrimary)),
                if (readoutCaption != null) ...[
                  const SizedBox(width: Space.xs + 2),
                  Flexible(child: Text(readoutCaption!, style: t.footnote)),
                ],
              ],
            ),
          ],
          const SizedBox(height: Space.lg),
          child,
        ],
      ),
    );
  }
}

/// The one numeric voice on the Stats screen: rounded, tabular, tight.
TextStyle figureStyle(AppThemeTokens t, double size) => t.textStyle(size, FontWeight.w700, t.textPrimary).copyWith(
      height: 1.05,
      letterSpacing: -size * 0.02,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
