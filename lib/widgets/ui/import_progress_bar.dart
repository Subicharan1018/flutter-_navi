import 'package:flutter/widgets.dart';

import '../../core/theme.dart';

/// The thin determinate bar under an import: accent on the outline colour. [value] null shows a short stub (the
/// total is not known yet).
class ImportProgressBar extends StatelessWidget {
  final double? value;
  const ImportProgressBar({super.key, this.value});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.outline)),
            FractionallySizedBox(
              widthFactor: value ?? 0.02,
              child: ColoredBox(color: t.accent),
            ),
          ],
        ),
      ),
    );
  }
}
