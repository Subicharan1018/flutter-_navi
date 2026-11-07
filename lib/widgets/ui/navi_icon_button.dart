import 'package:flutter/material.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../art/navi_icons.dart';

/// A small icon button for desktop chrome: our own glyph, a tooltip that names
/// it, a hover wash, and the white focus ring (not Material's). Replaces
/// `IconButton` anywhere the app draws its own focus language.
class NaviIconButton extends StatefulWidget {
  final NaviGlyph glyph;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double box;
  final Color? color;
  const NaviIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.size = 18,
    this.box = 32,
    this.color,
  });

  @override
  State<NaviIconButton> createState() => _NaviIconButtonState();
}

class _NaviIconButtonState extends State<NaviIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final on = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: NaviPressable(
            onTap: widget.onTap,
            radius: widget.box / 2,
            child: Container(
              width: widget.box,
              height: widget.box,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on && _hover ? t.hover : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: NaviIcon(widget.glyph, size: widget.size, color: widget.color ?? (on ? t.textSecondary : t.textMuted)),
            ),
          ),
        ),
      ),
    );
  }
}
