import 'package:flutter/material.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../art/navi_icons.dart';
import 'app_tab.dart';
import 'nav_stack.dart';

/// "Library › Albums › Abbey Road": where you are, on screens wide enough to
/// have room for it. Every step but the last is a link back to it; the arrow
/// at the left goes up one level. Collapses to nothing at a tab's root.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTab>(
      valueListenable: activeTab,
      builder: (context, tab, _) {
        final trail = tabTrails[tab]!;
        return ValueListenableBuilder<List<Route<dynamic>>>(
          valueListenable: trail.routes,
          builder: (context, _, _) {
            final crumbs = trail.crumbs;
            if (!trail.canPop || crumbs.length < 2) return const SizedBox(height: 0);
            return _Bar(crumbs: crumbs);
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final List<Crumb> crumbs;
  const _Bar({required this.crumbs});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: Colors.transparent, // the page's own ground shows through (see GroundSurface)
        border: Border(bottom: BorderSide(color: t.separatorOpaque, width: 0.5)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Back (Alt+←)',
            child: CupertinoClickable(
              onTap: popActiveTab,
              semanticLabel: 'Back',
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(child: NaviIcon(NaviGlyph.chevronLeft, size: 18, color: t.accent)),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true, // keeps the current page in view when the trail is long
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < crumbs.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                          child: NaviIcon(NaviGlyph.chevron, size: 12, color: t.textMuted),
                        ),
                      _CrumbLabel(crumb: crumbs[i], current: i == crumbs.length - 1),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CrumbLabel extends StatelessWidget {
  final Crumb crumb;
  final bool current;
  const _CrumbLabel({required this.crumb, required this.current});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
      child: Text(
        crumb.title,
        maxLines: 1,
        style: t.footnote.copyWith(
          color: current ? t.textPrimary : t.textSecondary,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    if (current) return label;
    return NaviFocusable(
      radius: Radii.thumb,
      onTap: () => popToCrumb(crumb),
      semanticLabel: 'Go to ${crumb.title}',
      child: label,
    );
  }
}
