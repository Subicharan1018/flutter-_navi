import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../utils/platform_utils.dart';
import '../art/navi_icons.dart';

// The app's one popup. Not a SnackBar: since Flutter 3.38 a SnackBar with an
// action never times out, it can only be swiped down (into Android's gesture
// bar), and it sits on top of the player controls.

/// How long a message stays.
const Duration kToastDuration = Duration(milliseconds: 2500);

/// Longer when there is something to tap ("Undo"), but it still leaves.
const Duration kToastActionDuration = Duration(seconds: 6);

/// The one popup on screen, if any.
_ToastEntry? _shown;

class _ToastEntry {
  _ToastEntry(this.overlay, this.message, this.actionLabel, this.onAction);

  final OverlayState overlay;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  late final OverlayEntry entry;

  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    if (identical(_shown, this)) _shown = null;
    // Even before its first frame: it is already in the overlay.
    entry.remove();
    entry.dispose();
  }
}

/// Shows [message] at the top of [overlay]. There is only ever one: a new
/// message replaces the old one, and the one already showing is left alone, so
/// repeating it (tapping a button that keeps failing) cannot keep it up.
void showToastOn(OverlayState overlay, String message, {String? actionLabel, VoidCallback? onAction}) {
  final current = _shown;
  if (current != null &&
      identical(current.overlay, overlay) &&
      overlay.mounted &&
      current.message == message &&
      current.actionLabel == actionLabel) {
    return;
  }
  current?.remove();
  final next = _ToastEntry(overlay, message, actionLabel, onAction);
  next.entry = OverlayEntry(builder: (_) => _Toast(next));
  _shown = next;
  overlay.insert(next.entry);
}

class _Toast extends StatefulWidget {
  const _Toast(this.data);
  final _ToastEntry data;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  Timer? _timer;
  Offset _drag = Offset.zero;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _in.forward();
    _timer = Timer(widget.data.actionLabel == null ? kToastDuration : kToastActionDuration, _leave);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    // The overlay went away with the popup still in it.
    if (identical(_shown, widget.data)) _shown = null;
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _in.reverse().orCancel.catchError((_) {});
    widget.data.remove();
  }

  /// Sideways or up, far or fast enough, throws it away. Down is left alone:
  /// from the top of the screen that is the way back to where it came from.
  void _dragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    final away = _drag.dx.abs() > 80 || _drag.dy < -32 || v.dx.abs() > 600 || v.dy < -600;
    if (away) {
      _timer?.cancel();
      widget.data.remove();
    } else {
      setState(() => _drag = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final data = widget.data;
    final action = data.actionLabel;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Transform.translate(
                offset: Offset(_drag.dx, _drag.dy < 0 ? _drag.dy : 0),
                child: FadeTransition(
                  opacity: _in,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, -0.4), end: Offset.zero)
                        .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      onDismiss: data.remove,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _leave,
                        onPanUpdate: (d) => setState(() => _drag += d.delta),
                        onPanEnd: _dragEnd,
                        child: Material(
                          color: t.bgElevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.group),
                            side: BorderSide(color: t.outline, width: 0.5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                                      child: Text(data.message, style: t.subheadline.copyWith(color: t.textPrimary)),
                                    ),
                                  ),
                                  if (action != null)
                                    TextButton(
                                      onPressed: () {
                                        if (_leaving) return;
                                        data.onAction?.call();
                                        _leave();
                                      },
                                      child: Text(action),
                                    ),
                                  if (PlatformUtils.isDesktop)
                                    IconButton(
                                      tooltip: 'Dismiss',
                                      visualDensity: VisualDensity.compact,
                                      icon: NaviIcon(NaviGlyph.close, size: 14, color: t.textMuted),
                                      onPressed: _leave,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
