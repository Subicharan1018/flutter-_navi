import 'package:flutter/material.dart';
import '../core/theme.dart';

// =============================================================================
// SwipeActionBackground
// Background revealed during a Dismissible swipe. Themed using ThemeTokens.
// =============================================================================

enum SwipeActionSide { left, right }

class SwipeActionBackground extends StatelessWidget {
  const SwipeActionBackground({
    super.key,
    required this.side,
    required this.icon,
    required this.label,
    required this.color,
  });

  final SwipeActionSide side;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLeft = side == SwipeActionSide.left;
    final tokens = ThemeTokens.of(context);
    return Container(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(
            color: tokens.outline.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
