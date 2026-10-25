import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../utils/platform_utils.dart';
import '../art/navi_icons.dart';

/// A horizontally scrolling row of cards with the cues a row needs when its
/// last card is cut off by the edge of the screen:
///
///  * the cut edge fades out instead of ending hard (left too, once scrolled);
///  * with a mouse, hovering shows arrow buttons that page the row;
///  * with a D-pad or Tab, moving focus scrolls the row (ListView already does).
///
/// Every shelf in the app uses this, so they all behave the same.
class HorizontalShelf extends StatefulWidget {
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final double height;
  final double gap;
  final EdgeInsets padding;

  const HorizontalShelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.gap = Space.md,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.gutter),
  });

  /// Width of the fade at a cut edge.
  static const double fade = 40;

  @override
  State<HorizontalShelf> createState() => _HorizontalShelfState();
}

class _HorizontalShelfState extends State<HorizontalShelf> {
  final ScrollController _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_measure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    final back = p.pixels > 1;
    final forward = p.pixels < p.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(int direction) {
    final p = _controller.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent);
    _controller.animateTo(target, duration: Motion.standard, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final fade = HorizontalShelf.fade;
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return false;
          },
          child: Stack(
            children: [
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final f = fade / bounds.width;
                  return LinearGradient(
                    colors: [
                      _canBack ? Colors.transparent : Colors.black,
                      Colors.black,
                      Colors.black,
                      _canForward ? Colors.transparent : Colors.black,
                    ],
                    stops: [0, f, 1 - f, 1],
                  ).createShader(bounds);
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
                  ),
                  child: ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: widget.padding,
                    itemCount: widget.itemCount,
                    separatorBuilder: (_, _) => SizedBox(width: widget.gap),
                    itemBuilder: widget.itemBuilder,
                  ),
                ),
              ),
              if (_hovered && PlatformUtils.isDesktop) ...[
                if (_canBack) _Arrow(left: true, onTap: () => _page(-1)),
                if (_canForward) _Arrow(left: false, onTap: () => _page(1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final bool left;
  final VoidCallback onTap;
  const _Arrow({required this.left, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Positioned(
      left: left ? Space.sm : null,
      right: left ? null : Space.sm,
      top: 0,
      bottom: 44, // centre on the artwork, not on the caption below it
      child: Center(
        child: Tooltip(
          message: left ? 'Scroll left' : 'Scroll right',
          child: NaviFocusable(
            radius: Radii.capsule,
            onTap: onTap,
            hoverTint: false,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.bgOverlay,
                shape: BoxShape.circle,
                border: Border.all(color: t.outline, width: 0.5),
              ),
              child: Center(
                child: NaviIcon(left ? NaviGlyph.chevronLeft : NaviGlyph.chevron, size: 18, color: t.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
