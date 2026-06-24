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
// NaviCard — Base Card Component
// =============================================================================
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
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.02);

    return AnimatedContainer(
      duration: kAnimNormal,
      decoration: BoxDecoration(
        color: color ?? defaultBg,
        borderRadius: radiusMd,
        border: Border.all(
          color: tokens.textPrimary.withValues(alpha: 0.08),
          width: 0.5,
        ),
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
// PremiumCard — Double-Bezel, Neumorphic, or Stark Brutalist card layout
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
    final mode = tokens.mode;

    Widget current;

    switch (mode) {
      case AppThemeMode.zen:
        // Stark Zen layout: sharp corners, thin black border, no shadow
        current = Container(
          padding: padding ?? const EdgeInsets.all(s20),
          decoration: BoxDecoration(
            color: color ?? tokens.bgBase,
            border: Border.all(color: tokens.textPrimary, width: 1.0),
          ),
          child: child,
        );
        break;

      case AppThemeMode.neumorphic:
        // Neumorphic extruded soft surface
        current = Container(
          padding: padding ?? const EdgeInsets.all(s20),
          decoration: BoxDecoration(
            color: color ?? tokens.bgBase,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: tokens.neuDark.withValues(alpha: 0.5),
                offset: const Offset(6, 6),
                blurRadius: 14,
              ),
              BoxShadow(
                color: tokens.neuLight,
                offset: const Offset(-6, -6),
                blurRadius: 14,
              ),
            ],
          ),
          child: child,
        );
        break;

      case AppThemeMode.frost:
        // Frost Double-Bezel: Frosted glass panel inside a transparent border rim
        final outerRadius = BorderRadius.circular(28);
        final innerRadius = BorderRadius.circular(22); // 28 - 6
        current = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: outerRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: innerRadius,
            child: Container(
              padding: padding ?? const EdgeInsets.all(s20),
              decoration: BoxDecoration(
                color: color ?? tokens.glassBg,
                borderRadius: innerRadius,
                border: Border.all(color: tokens.glassBorder, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
        break;

      case AppThemeMode.aura:
        // Aura Double-Bezel: OLED card inside a glowing neon accent highlight border rim
        final outerRadius = BorderRadius.circular(28);
        final innerRadius = BorderRadius.circular(22);
        current = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tokens.bgSurface.withValues(alpha: 0.4),
            borderRadius: outerRadius,
            border: Border.all(
              color: tokens.accent.withValues(alpha: 0.15),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.accent.withValues(alpha: 0.03),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Container(
            padding: padding ?? const EdgeInsets.all(s20),
            decoration: BoxDecoration(
              color: color ?? tokens.bgSurface,
              borderRadius: innerRadius,
              border: Border.all(
                color: tokens.textPrimary.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        );
        break;

      case AppThemeMode.analog:
        // Warm retro vinyl card with double border
        final outerRadius = BorderRadius.circular(24);
        final innerRadius = BorderRadius.circular(18);
        current = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tokens.bgSurface.withValues(alpha: 0.5),
            borderRadius: outerRadius,
            border: Border.all(
              color: tokens.outline.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Container(
            padding: padding ?? const EdgeInsets.all(s20),
            decoration: BoxDecoration(
              color: color ?? tokens.bgSurface,
              borderRadius: innerRadius,
              border: Border.all(
                color: tokens.outline.withValues(alpha: 0.5),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.outline.withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        );
        break;

      case AppThemeMode.spotify:
        // Spotify Double-Bezel: base dark surface inside slightly offset outer border rim
        final outerRadius = BorderRadius.circular(24);
        final innerRadius = BorderRadius.circular(18);
        current = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(alpha: 0.02),
            borderRadius: outerRadius,
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.04),
              width: 0.5,
            ),
          ),
          child: Container(
            padding: padding ?? const EdgeInsets.all(s20),
            decoration: BoxDecoration(
              color: color ?? tokens.bgSurface,
              borderRadius: innerRadius,
              border: Border.all(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        );
        break;
    }

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
            color: tokens.accent.withValues(alpha: 0.12),
            border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.2),
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
