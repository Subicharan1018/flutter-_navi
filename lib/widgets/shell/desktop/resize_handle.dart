import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// A draggable divider between two panes. Sits on the seam (a few pixels either
/// side) and shows the resize cursor; the line brightens on hover and drag.
/// [onDrag] gets the pointer's horizontal travel since the last event, in the
/// direction of growth for the pane it resizes: [growsRight] true when dragging
/// right widens the pane (the left rail), false when it narrows it (the right
/// panel). Double-click resets; with focus, ← and → resize by 16.
class ResizeHandle extends StatefulWidget {
  final bool growsRight;
  final void Function(double delta) onDrag;
  final VoidCallback onEnd;
  final VoidCallback onReset;
  final String label;

  const ResizeHandle({
    super.key,
    required this.growsRight,
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
    required this.label,
  });

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _drag = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final lit = _hover || _drag || _focus;
    return Semantics(
      label: widget.label,
      child: Focus(
        onFocusChange: (f) => setState(() => _focus = f),
        onKeyEvent: (_, e) {
          if (e is KeyUpEvent) return KeyEventResult.ignored;
          final dir = e.logicalKey == LogicalKeyboardKey.arrowRight
              ? 1.0
              : e.logicalKey == LogicalKeyboardKey.arrowLeft
                  ? -1.0
                  : 0.0;
          if (dir == 0) return KeyEventResult.ignored;
          widget.onDrag(16 * dir * (widget.growsRight ? 1 : -1));
          widget.onEnd();
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => setState(() => _drag = true),
            onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx * (widget.growsRight ? 1 : -1)),
            onHorizontalDragCancel: () => setState(() => _drag = false),
            onHorizontalDragEnd: (_) {
              setState(() => _drag = false);
              widget.onEnd();
            },
            onDoubleTap: widget.onReset,
            child: SizedBox(
              width: 8,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: lit ? 2 : 0.5,
                  color: lit ? t.textSecondary : t.separatorOpaque,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
