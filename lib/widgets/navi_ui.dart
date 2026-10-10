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
const Curve kCurveDecel = Curves.decelerate;

// =============================================================================
// PremiumCard — the one card surface: solid, borderless, 8 px corners.
// =============================================================================
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    Widget current;

    current = Container(
        padding: padding ?? const EdgeInsets.all(s16),
        decoration: BoxDecoration(
          color: color ?? tokens.bgSurface,
          borderRadius: radiusSm,
        ),
        child: child,
      );

    if (onTap == null) return current;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: current,
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
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: tokens.textPrimary.withValues(alpha: _anim.value * 0.1),
          borderRadius: widget.borderRadius ?? radiusSm,
        ),
      ),
    );
  }
}
