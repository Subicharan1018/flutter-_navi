import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Renders a single lyric line with Apple Music–style animations.
///
/// Line states:
///   active   — large, bold, full opacity, 1.05× scale
///   upcoming — normal size, 0.60 opacity
///   past     — normal size, 0.35 opacity
class LyricLineWidget extends StatelessWidget {
  final String text;
  final bool isActive;
  final bool isPast;

  /// Index in the overall list — used to stagger the entry animation.
  final int index;

  /// Whether this line is being shown for the first time (triggers entry anim).
  final bool animate;

  const LyricLineWidget({
    super.key,
    required this.text,
    required this.isActive,
    required this.isPast,
    required this.index,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final targetOpacity = isActive
        ? 1.0
        : isPast
        ? 0.35
        : 0.55;

    final targetFontSize = isActive ? 34.0 : 26.0;
    final targetWeight = isActive ? FontWeight.w800 : FontWeight.w700;
    final targetColor = Colors.white.withValues(alpha: targetOpacity);

    Widget line = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: targetFontSize,
        fontWeight: targetWeight,
        color: targetColor,
        height: 1.32,
        letterSpacing: isActive ? -0.8 : -0.4,
        shadows: isActive
            ? [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.60),
                  blurRadius: 26,
                ),
                const Shadow(
                  color: Colors.black54,
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : [
                const Shadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.94,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Text(text, maxLines: null),
        ),
      ),
    );

    // Entry animation: fade + slide up, staggered per line
    if (animate) {
      line = line
          .animate(delay: Duration(milliseconds: 60 * index))
          .fadeIn(duration: 350.ms, curve: Curves.easeOut)
          .slideY(begin: 0.15, end: 0, duration: 350.ms, curve: Curves.easeOut);
    }

    return line;
  }
}
