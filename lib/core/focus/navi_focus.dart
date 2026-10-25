import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform_utils.dart';
import '../theme.dart';

// =============================================================================
// navi_focus.dart — the app's focus language for remotes and keyboards.
//
// [NaviFocusRing] makes any widget a D-pad / keyboard target:
//   * a monochrome ring (the accent, with a hairline of the page colour inside
//     it so it reads on artwork too), shown only while the user is navigating
//     with keys, never after a touch;
//   * Select / Enter / Space / gamepad A activate [onTap];
//   * holding Select, or pressing the Menu key, runs [onLongPress] (the
//     context menu), the way a long press does on a phone;
//   * on a TV the focused item lifts a few percent.
//
// [NaviFocusable] adds the pointer side: click, right-click and a hover tint.
// =============================================================================

/// Raised by the Menu key and a held Select.
class NaviContextIntent extends Intent {
  const NaviContextIntent();
}

/// How long Select must be held to count as a long press.
const Duration kRemoteLongPress = Duration(milliseconds: 500);

bool _isActivateKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA ||
    k == LogicalKeyboardKey.space;

/// Whether the focus ring should currently show (keys, not touch).
bool get _navigatingByKey =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

class NaviFocusRing extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final double radius;

  /// Lift the child while focused. Defaults to on for TV only.
  final bool? lift;

  /// Draw the ring (off for items that restyle themselves when focused).
  final bool showRing;

  /// Called when focus enters or leaves (e.g. to restyle the child).
  final ValueChanged<bool>? onFocusChange;

  const NaviFocusRing({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.radius = Radii.cover,
    this.lift,
    this.showRing = true,
    this.onFocusChange,
  });

  @override
  State<NaviFocusRing> createState() => _NaviFocusRingState();
}

class _NaviFocusRingState extends State<NaviFocusRing> {
  FocusNode? _own;
  FocusNode get _node =>
      widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'NaviFocusRing'));
  bool _focused = false;
  Timer? _hold;
  bool _longFired = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _hold?.cancel();
    _own?.dispose();
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) {
    if (mounted && _focused) setState(() {});
  }

  void _focusChanged(bool focused) {
    _hold?.cancel();
    if (!focused) _longFired = false;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu && event is KeyDownEvent) {
      final handler = widget.onLongPress;
      if (handler == null) return KeyEventResult.ignored;
      handler();
      return KeyEventResult.handled;
    }
    if (!_isActivateKey(key) || !_enabled) return KeyEventResult.ignored;

    // Without a long-press action Select fires at once: no delay to feel.
    if (widget.onLongPress == null) {
      if (event is KeyDownEvent) widget.onTap?.call();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      _longFired = false;
      _hold?.cancel();
      _hold = Timer(kRemoteLongPress, () {
        _longFired = true;
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call();
      });
    } else if (event is KeyUpEvent) {
      final pending = _hold?.isActive ?? false;
      _hold?.cancel();
      if (pending && !_longFired) widget.onTap?.call();
      _longFired = false;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final tv = PlatformUtils.isTv;
    final show = _focused && _navigatingByKey && widget.showRing;
    final lift = widget.lift ?? tv;
    final ring = tv ? 3.0 : 2.0;
    final gap = tv ? 4.0 : 2.0;
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: _enabled,
      onFocusChange: _focusChanged,
      onKeyEvent: _onKey,
      child: AnimatedScale(
        scale: show && lift ? 1.05 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        // The ring sits just outside the child so a pill-shaped child is never
        // clipped by a rounded-rect ring (and the ring never covers content).
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (show)
              Positioned(
                left: -gap,
                top: -gap,
                right: -gap,
                bottom: -gap,
                child: IgnorePointer(
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius + gap),
                      border: Border.all(color: t.accent, width: ring),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [NaviFocusRing] plus the pointer: click, right-click, hover tint.
class NaviFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Right-click; defaults to [onLongPress] so a context menu opens either way.
  final VoidCallback? onSecondaryTap;
  final double radius;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;

  /// Tint the child on mouse hover. Off for children that draw their own.
  final bool hoverTint;

  const NaviFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.radius = Radii.cover,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.hoverTint = true,
  });

  @override
  State<NaviFocusable> createState() => _NaviFocusableState();
}

class _NaviFocusableState extends State<NaviFocusable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final secondary = widget.onSecondaryTap ?? widget.onLongPress;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget body = widget.child;
    if (widget.hoverTint && _hovered && enabled) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: t.fill,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: body,
      );
    }
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: NaviFocusRing(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          radius: widget.radius,
          autofocus: widget.autofocus,
          focusNode: widget.focusNode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onSecondaryTapUp: secondary == null ? null : (_) => secondary(),
            child: body,
          ),
        ),
      ),
    );
  }
}
