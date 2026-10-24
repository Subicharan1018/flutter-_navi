import 'package:flutter/widgets.dart';

/// Fades a scrolling pane out at its top and bottom edges instead of
/// cutting rows off hard against the header or the controls.
class EdgeFade extends StatelessWidget {
  /// Fraction of the height faded at each edge.
  final double top;
  final double bottom;
  final Widget child;

  const EdgeFade({super.key, this.top = 0.05, this.bottom = 0.1, required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [0, top, 1 - bottom, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
