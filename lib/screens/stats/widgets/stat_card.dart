import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';

/// How loudly a section speaks: [loud] opens a new movement of the page,
/// [quiet] is a footnote-weight aside, [normal] the default.
enum StatEmphasis { quiet, normal, loud }

/// One question on the Stats page, set straight on the page with no card
/// around it: a section title, its one-line answer large underneath, then
/// the chart or list that backs it up. Sections are separated by space alone.
class StatSection extends StatelessWidget {
  final StatEmphasis emphasis;
  final String title;

  /// The headline answer, e.g. "9 pm" or "+12%". Shown large, in [readoutColor].
  final String? readout;
  final String? readoutCaption;
  final Color? readoutColor;

  /// Right of the title, e.g. a "See All" or a legend.
  final Widget? trailing;
  final Widget child;

  const StatSection({
    super.key,
    required this.title,
    this.readout,
    this.readoutCaption,
    this.readoutColor,
    this.trailing,
    this.emphasis = StatEmphasis.normal,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: switch (emphasis) {
          StatEmphasis.quiet => Space.xxl,
          StatEmphasis.normal => Space.xxxl + Space.sm,
          StatEmphasis.loud => Space.huge + Space.xl,
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: switch (emphasis) {
                      StatEmphasis.quiet => t.headline.copyWith(color: t.textSecondary),
                      StatEmphasis.normal => t.title2,
                      StatEmphasis.loud => t.title1,
                    },
                  ),
                ),),
              ?trailing,
            ],
          ),
          if (readout != null) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: Space.sm,
              children: [
                Text(readout!, style: figureStyle(t, 30).copyWith(color: readoutColor ?? t.textPrimary)),
                if (readoutCaption != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(readoutCaption!, style: t.subheadline),
                  ),
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

/// The one numeric voice on the Stats screen: display cut, tabular, tight.
TextStyle figureStyle(AppThemeTokens t, double size) => t.textStyle(size, FontWeight.w700, t.textPrimary).copyWith(
      height: 1.05,
      letterSpacing: -size * 0.02,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
