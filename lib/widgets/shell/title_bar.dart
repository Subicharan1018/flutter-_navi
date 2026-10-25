import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../utils/platform_utils.dart';

/// Windows only: the window's title bar drawn by the app, so the chrome matches
/// the page and the window controls sit on it. Drag it to move the window,
/// double-click to maximise, and the three buttons behave as Windows ones do.
class NaviTitleBar extends StatefulWidget {
  const NaviTitleBar({super.key});

  /// Whether the app draws its own title bar on this platform.
  static bool get enabled => PlatformUtils.isWindows;

  static const double height = 36;

  @override
  State<NaviTitleBar> createState() => _NaviTitleBarState();
}

class _NaviTitleBarState extends State<NaviTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximise() async => await windowManager.isMaximized()
      ? windowManager.unmaximize()
      : windowManager.maximize();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // A Material ancestor gives the text the app's default style (without one
    // it is drawn with the framework's debug underline).
    return Material(
      color: t.bgSurface,
      child: SizedBox(
        height: NaviTitleBar.height,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximise,
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'NaviVibe',
                      style: t.footnote.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _CaptionButton(
              kind: _Caption.minimise,
              onTap: windowManager.minimize,
            ),
            _CaptionButton(
              kind: _maximized ? _Caption.restore : _Caption.maximise,
              onTap: _toggleMaximise,
            ),
            _CaptionButton(kind: _Caption.close, onTap: windowManager.close),
          ],
        ),
      ),
    );
  }
}

enum _Caption { minimise, maximise, restore, close }

class _CaptionButton extends StatefulWidget {
  final _Caption kind;
  final VoidCallback onTap;
  const _CaptionButton({required this.kind, required this.onTap});

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final close = widget.kind == _Caption.close;
    // Windows paints Close red on hover; everything else is a neutral lift.
    final hover = close ? t.danger : t.fill;
    final ink = close && _hovered ? Colors.white : t.textPrimary;
    return Semantics(
      button: true,
      label: switch (widget.kind) {
        _Caption.minimise => 'Minimise',
        _Caption.maximise => 'Maximise',
        _Caption.restore => 'Restore',
        _Caption.close => 'Close',
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: NaviTitleBar.height,
            color: _hovered ? hover : Colors.transparent,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _CaptionPainter(widget.kind, ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionPainter extends CustomPainter {
  final _Caption kind;
  final Color color;
  const _CaptionPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    switch (kind) {
      case _Caption.minimise:
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), p);
      case _Caption.maximise:
        canvas.drawRect(Rect.fromLTWH(0.5, 0.5, w - 1, h - 1), p);
      case _Caption.restore:
        canvas.drawRect(Rect.fromLTWH(0.5, 2.5, w - 2.5, h - 2.5), p);
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 2.5)
            ..lineTo(2.5, 0.5)
            ..lineTo(w - 0.5, 0.5)
            ..lineTo(w - 0.5, h - 2.5)
            ..lineTo(w - 2.5, h - 2.5),
          p,
        );
      case _Caption.close:
        canvas.drawLine(const Offset(0, 0), Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(0, h), p);
    }
  }

  @override
  bool shouldRepaint(_CaptionPainter old) =>
      old.kind != kind || old.color != color;
}
