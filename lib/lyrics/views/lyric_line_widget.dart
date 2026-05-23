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
            : 0.60;

    final targetFontSize = isActive ? 28.0 : 22.0;
    final targetWeight =
        isActive ? FontWeight.w700 : FontWeight.w400;
    final targetColor = Colors.white.withValues(alpha: targetOpacity);

    Widget line = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      style: TextStyle(
        fontSize: targetFontSize,
        fontWeight: targetWeight,
        color: targetColor,
        height: 1.3,
        letterSpacing: isActive ? -0.3 : 0.0,
      ),
      child: AnimatedScale(
        scale: isActive ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 28.0,
            vertical: 10.0,
          ),
          child: Text(
            text,
            maxLines: null,
          ),
        ),
      ),
    );

    // Entry animation: fade + slide up, staggered per line
    if (animate) {
      line = line
          .animate(delay: Duration(milliseconds: 60 * index))
          .fadeIn(duration: 350.ms, curve: Curves.easeOut)
          .slideY(
            begin: 0.15,
            end: 0,
            duration: 350.ms,
            curve: Curves.easeOut,
          );
    }

    return line;
  }
}
