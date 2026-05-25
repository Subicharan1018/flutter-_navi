import 'package:flutter/material.dart';
import '../core/theme.dart';

// =============================================================================
// Spacing & Radius Scale
// =============================================================================
const double s4 = 4.0;
const double s8 = 8.0;
const double s12 = 12.0;
const double s16 = 16.0;
const double s20 = 20.0;
const double s24 = 24.0;
const double s32 = 32.0;

const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
const BorderRadius radiusMd = BorderRadius.all(Radius.circular(12));
const BorderRadius radiusLg = BorderRadius.all(Radius.circular(16));
const BorderRadius radiusXl = BorderRadius.all(Radius.circular(24));
const BorderRadius radiusFull = BorderRadius.all(Radius.circular(999));

// =============================================================================
// Animation Defaults
// =============================================================================
const Duration kAnimFast = Duration(milliseconds: 150);
const Duration kAnimNormal = Duration(milliseconds: 250);
const Duration kAnimSlow = Duration(milliseconds: 400);

const Curve kCurveStandard = Curves.easeInOut;
const Curve kCurveSpring = Curves.elasticOut;
const Curve kCurveDecel = Curves.decelerate;

// =============================================================================
// NaviCard — Base Card Component
// =============================================================================
class NaviCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;

  const NaviCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.02);

    return AnimatedContainer(
      duration: kAnimNormal,
      decoration: BoxDecoration(
        color: color ?? defaultBg,
        borderRadius: radiusMd,
        border: Border.all(
          color: tokens.textPrimary.withOpacity(0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.04),
            offset: const Offset(0, 1),
            blurRadius: 0,
            spreadRadius: -1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radiusMd,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(s20),
            child: child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// NaviSkeleton — Shimmer Loading Skeleton
// =============================================================================
class NaviSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const NaviSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius,
  });

  @override
  State<NaviSkeleton> createState() => _NaviSkeletonState();
}

class _NaviSkeletonState extends State<NaviSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: tokens.textPrimary.withOpacity(_anim.value * 0.1),
          borderRadius: widget.borderRadius ?? radiusSm,
        ),
      ),
    );
  }
}

// =============================================================================
// LiquidGlassButton — Interactive CTA
// =============================================================================
class LiquidGlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;

  const LiquidGlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.isLoading = false,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: kAnimFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: kCurveStandard));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return GestureDetector(
      onTapDown: (_) {
        _ctrl.forward();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        _ctrl.reverse();
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () {
        _ctrl.reverse();
        setState(() => _pressed = false);
      },
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: s24),
          decoration: BoxDecoration(
            borderRadius: radiusFull,
            color: tokens.accent.withOpacity(0.12),
            border: Border.all(color: tokens.accent.withOpacity(0.4)),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: tokens.accent.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: tokens.accent, size: 18),
                const SizedBox(width: s8),
              ],
              if (widget.isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                )
              else
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
