import 'package:flutter/material.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../art/navi_icons.dart';

/// The one "sort" control on desktop pages: what it is sorted by now, and a
/// chevron that says it opens a menu. Library, Songs, Albums and Playlists use
/// it, so a sort looks the same everywhere.
class SortMenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SortMenuButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Sort by $label',
      child: NaviFocusable(
        radius: 8,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.subheadline.copyWith(color: t.textPrimary)),
              const SizedBox(width: Space.xs),
              NaviIcon(NaviGlyph.chevronDown, size: 12, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
