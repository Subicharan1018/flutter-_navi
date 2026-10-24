import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';

/// One supporting figure: an icon, the value (any widget: a rolling number, a
/// ring), and a label. Presses in like every control in the app when it has
/// an [onTap].
class StatTile extends StatelessWidget {
  final NaviGlyph? glyph;
  final Widget value;
  final String label;
  final VoidCallback? onTap;

  const StatTile({super.key, this.glyph, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (glyph != null) ...[NaviIcon(glyph!, size: 18, color: t.textSecondary), const SizedBox(height: Space.xs)],
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
        const SizedBox(height: Space.xxs),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
      ],
    );
    return onTap == null ? body : CupertinoClickable(onTap: onTap, scaleFactor: 0.97, child: body);
  }
}
