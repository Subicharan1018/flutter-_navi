import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// AppThemeMode — enum identifying each of the five themes
// =============================================================================

enum AppThemeMode {
  /// Spotify-accurate dark palette (original).
  spotify,

  /// Dynamic mesh-gradient dark theme — album art drives colour.
  aura,

  /// Glassmorphism / frosted-glass iOS aesthetic.
  frost,

  /// Neumorphic soft-UI — extruded surfaces.
  neumorphic,

  /// Retro vinyl / analogue warmth.
  analog,

  /// Ultra-minimalist typography-led brutalist design.
  zen,
}

extension AppThemeModeLabel on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.spotify:
        return 'Spotify';
      case AppThemeMode.aura:
        return 'Aura';
      case AppThemeMode.frost:
        return 'Frost';
      case AppThemeMode.neumorphic:
        return 'Neumorphic';
      case AppThemeMode.analog:
        return 'Analog';
      case AppThemeMode.zen:
        return 'Zen';
    }
  }

  String get description {
    switch (this) {
      case AppThemeMode.spotify:
        return 'Classic Spotify dark palette — crisp, green-accented, immersive.';
      case AppThemeMode.aura:
        return 'Deep black with dynamic mesh gradients drawn from album art.';
      case AppThemeMode.frost:
        return 'Frosted-glass panels over a blurred album backdrop.';
      case AppThemeMode.neumorphic:
        return 'Soft extruded surfaces — tactile, physical, premium.';
      case AppThemeMode.analog:
        return 'Warm vinyl-era nostalgia in cream, wood, and brushed metal.';
      case AppThemeMode.zen:
        return 'Stark, typography-led minimalism with zero distractions.';
    }
  }
}

// =============================================================================
// AppThemeTokens — the raw palette/typography tokens for one theme.
// Every theme produces an instance of this class; the rest of the app reads
// from it via the ThemeTokens InheritedWidget below.
// =============================================================================

class AppThemeTokens {
  // ── Identity ────────────────────────────────────────────────────────────────
  final AppThemeMode mode;

  // ── Background layers (darkest → brightest) ─────────────────────────────────
  final Color bgBase; // scaffold / page background
  final Color bgSurface; // cards, sheets
  final Color bgElevated; // popovers, tooltips
  final Color bgOverlay; // modal scrims

  // ── Brand / accent ────────────────────────────────────────────────────────
  final Color accent; // primary interactive colour
  final Color accentDim; // muted accent (disabled, inactive)
  final Color gold; // stars / favourites

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Borders & dividers ────────────────────────────────────────────────────
  final Color outline;

  // ── Glassmorphism (used by Frost; others can safely ignore) ──────────────
  final Color glassBg;
  final Color glassBorder;

  // ── Neumorphic shadows (used by Neumorphic theme) ─────────────────────────
  final Color neuLight; // bright-side shadow colour
  final Color neuDark; // dark-side shadow colour

  // ── Typography ────────────────────────────────────────────────────────────
  final TextStyle Function(double size, FontWeight weight, Color color)
  textStyle;

  const AppThemeTokens({
    required this.mode,
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgOverlay,
    required this.accent,
    required this.accentDim,
    required this.gold,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.outline,
    required this.glassBg,
    required this.glassBorder,
    required this.neuLight,
    required this.neuDark,
    required this.textStyle,
  });

  // ── Convenience text styles ───────────────────────────────────────────────
  TextStyle get headingLg => textStyle(28, FontWeight.w700, textPrimary);
  TextStyle get headingMd => textStyle(22, FontWeight.w700, textPrimary);
  TextStyle get headingSm => textStyle(16, FontWeight.w700, textPrimary);
  TextStyle get bodyMd => textStyle(14, FontWeight.w400, textPrimary);
  TextStyle get bodySm => textStyle(12, FontWeight.w400, textSecondary);
  TextStyle get labelMd => textStyle(11, FontWeight.w600, textSecondary);
  TextStyle get technicalSm => textStyle(14, FontWeight.w500, textSecondary);
  TextStyle get technicalXs => textStyle(12, FontWeight.w400, textMuted);

  /// Whether this theme uses a light background
  bool get isLight => ThemeVariants._isLight(mode);

  /// Guaranteed opaque surface colour — safe for dropdowns, dialogs,
  /// and other overlays where a translucent [bgSurface] would leak the
  /// backdrop through (e.g. the Frost theme's 30% white glass surface).
  Color get bgSurfaceOpaque => Color.alphaBlend(bgSurface, bgBase);
}

// =============================================================================
// ThemeVariants — builds an AppThemeTokens for every AppThemeMode
// =============================================================================

class ThemeVariants {
  ThemeVariants._();

  static bool _isLight(AppThemeMode m) =>
      m == AppThemeMode.neumorphic ||
      m == AppThemeMode.zen ||
      m == AppThemeMode.analog;

  // ── Spotify ─────────────────────────────────────────────────────────────────
  static AppThemeTokens spotify() => AppThemeTokens(
    mode: AppThemeMode.spotify,
    bgBase: const Color(0xFF000000),
    bgSurface: const Color(0xFF121212),
    bgElevated: const Color(0xFF181818),
    bgOverlay: const Color(0xFF282828),
    accent: const Color(0xFF1DB954),
    accentDim: const Color(0xFF158A3E),
    gold: const Color(0xFFE8C547),
    textPrimary: const Color(0xFFFFFFFF),
    textSecondary: const Color(0xFFB3B3B3),
    textMuted: const Color(0xFF7F7F7F),
    outline: const Color(0xFF2A2A2A),
    glassBg: const Color(0xCC121212),
    glassBorder: const Color(0x28FFFFFF),
    neuLight: const Color(0xFF282828),
    neuDark: const Color(0xFF000000),
    textStyle: (size, weight, color) =>
        GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color),
  );

  // ── Aura — deep black + dynamic gradients ────────────────────────────────
  static AppThemeTokens aura() => AppThemeTokens(
    mode: AppThemeMode.aura,
    bgBase: const Color(0xFF030303),
    bgSurface: const Color(0xFF0D0D0D),
    bgElevated: const Color(0xFF141414),
    bgOverlay: const Color(0xFF1A1A2E),
    // Purple-pink accent: aura vibe
    accent: const Color(0xFFBB86FC),
    accentDim: const Color(0xFF7B54A8),
    gold: const Color(0xFFFFD700),
    textPrimary: const Color(0xFFF0EEFF),
    textSecondary: const Color(0xFFAA99CC),
    textMuted: const Color(0xFF665588),
    outline: const Color(0xFF1E1E30),
    glassBg: const Color(0xAA0D0D1A),
    glassBorder: const Color(0x33BB86FC),
    neuLight: const Color(0xFF1A1A2E),
    neuDark: const Color(0xFF000000),
    textStyle: (size, weight, color) => GoogleFonts.spaceMono(
      fontSize: size * 0.95,
      fontWeight: weight,
      color: color,
    ),
  );

  // ── Frost — glassmorphism ─────────────────────────────────────────────────
  static AppThemeTokens frost() => AppThemeTokens(
    mode: AppThemeMode.frost,
    bgBase: const Color(0xFF0A1628),
    bgSurface: const Color(0x4DFFFFFF), // translucent white glass
    bgElevated: const Color(0x66FFFFFF),
    bgOverlay: const Color(0x33FFFFFF),
    accent: const Color(0xFF64D2FF), // ice blue
    accentDim: const Color(0xFF3BA8D8),
    gold: const Color(0xFFFFE066),
    textPrimary: const Color(0xFFFFFFFF),
    textSecondary: const Color(0xCCFFFFFF),
    textMuted: const Color(0x88FFFFFF),
    outline: const Color(0x33FFFFFF),
    glassBg: const Color(0x55FFFFFF),
    glassBorder: const Color(0x55FFFFFF),
    neuLight: const Color(0x55FFFFFF),
    neuDark: const Color(0x330A1628),
    textStyle: (size, weight, color) =>
        GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color),
  );

  // ── Neumorphic — soft-UI light ────────────────────────────────────────────
  static AppThemeTokens neumorphic() => AppThemeTokens(
    mode: AppThemeMode.neumorphic,
    bgBase: const Color(0xFFE0E5EC),
    bgSurface: const Color(0xFFE8EDF4),
    bgElevated: const Color(0xFFF0F4FA),
    bgOverlay: const Color(0xFFD8DDE8),
    accent: const Color(0xFF4A90D9), // calm blue
    accentDim: const Color(0xFF2D6BAD),
    gold: const Color(0xFFD4A017),
    textPrimary: const Color(0xFF2C3E50),
    textSecondary: const Color(0xFF5D7A8C),
    textMuted: const Color(0xFF8FA8B8),
    outline: const Color(0xFFCDD3DE),
    glassBg: const Color(0xCCE0E5EC),
    glassBorder: const Color(0x44FFFFFF),
    neuLight: const Color(0xFFFFFFFF), // key for neumorphic shadows
    neuDark: const Color(0xFFA3B1C6),
    textStyle: (size, weight, color) =>
        GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color),
  );

  // ── Analog / Vinyl — warm retro ──────────────────────────────────────────
  static AppThemeTokens analog() => AppThemeTokens(
    mode: AppThemeMode.analog,
    bgBase: const Color(0xFFF5ECD7), // aged cream
    bgSurface: const Color(0xFFEDE0C4),
    bgElevated: const Color(0xFFDED0B0),
    bgOverlay: const Color(0xFF3D2B1F), // dark wood for overlays
    accent: const Color(0xFFB5451B), // oxide red / vinyl groove
    accentDim: const Color(0xFF8A3315),
    gold: const Color(0xFFC8960C),
    textPrimary: const Color(0xFF1C1008),
    textSecondary: const Color(0xFF5C3D2E),
    textMuted: const Color(0xFF9E7B5A),
    outline: const Color(0xFFCAB896),
    glassBg: const Color(0xCCEDE0C4),
    glassBorder: const Color(0x44B5451B),
    neuLight: const Color(0xFFFFF8E8),
    neuDark: const Color(0xFFB09070),
    textStyle: (size, weight, color) => GoogleFonts.playfairDisplay(
      fontSize: size,
      fontWeight: weight,
      color: color,
    ),
  );

  // ── Zen — ultra-minimalist, typography-led ────────────────────────────────
  static AppThemeTokens zen() => AppThemeTokens(
    mode: AppThemeMode.zen,
    bgBase: const Color(0xFFFAFAF8), // near-white
    bgSurface: const Color(0xFFF0F0EE),
    bgElevated: const Color(0xFFE8E8E4),
    bgOverlay: const Color(0xFF111111),
    accent: const Color(0xFF111111), // pure black accent
    accentDim: const Color(0xFF555555),
    gold: const Color(0xFF222222), // even stars are monochrome
    textPrimary: const Color(0xFF0A0A0A),
    textSecondary: const Color(0xFF444444),
    textMuted: const Color(0xFF888888),
    outline: const Color(0xFFDDDDDD),
    glassBg: const Color(0xCCFAFAF8),
    glassBorder: const Color(0x22000000),
    neuLight: const Color(0xFFFFFFFF),
    neuDark: const Color(0xFFCCCCCC),
    // Scale clamped to 1.08× (was 1.15×) to prevent card text overflow.
    textStyle: (size, weight, color) => GoogleFonts.cormorantGaramond(
      fontSize: size * 1.08,
      fontWeight: weight,
      color: color,
      letterSpacing: weight == FontWeight.w700 ? -0.5 : 0.2,
    ),
  );

  // ── Factory ───────────────────────────────────────────────────────────────
  static AppThemeTokens of(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.spotify:
        return spotify();
      case AppThemeMode.aura:
        return aura();
      case AppThemeMode.frost:
        return frost();
      case AppThemeMode.neumorphic:
        return neumorphic();
      case AppThemeMode.analog:
        return analog();
      case AppThemeMode.zen:
        return zen();
    }
  }
}

// =============================================================================
// ThemeTokens — InheritedWidget so any descendant can call
//   ThemeTokens.of(context).accent, etc.
// =============================================================================

class ThemeTokens extends InheritedWidget {
  final AppThemeTokens tokens;

  const ThemeTokens({super.key, required this.tokens, required super.child});

  static AppThemeTokens of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<ThemeTokens>();
    assert(w != null, 'No ThemeTokens found in widget tree');
    return w!.tokens;
  }

  @override
  bool updateShouldNotify(ThemeTokens old) => old.tokens.mode != tokens.mode;
}

// =============================================================================
// AppTheme — builds a ThemeData from an AppThemeTokens instance.
//             Also exposes legacy static members used across the codebase.
// =============================================================================

class AppTheme {
  // ── Legacy static colours (Spotify defaults, kept for backward compat) ────
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color electricBlue = Color(0xFF1DB954);
  static const Color goldAccent = Color(0xFFE8C547);

  static const Color coreBackground = Color(0xFF000000);
  static const Color surfaceLevel = Color(0xFF121212);
  static const Color cardSurface = Color(0xFF181818);
  static const Color topLevel = Color(0xFF282828);
  static const Color outlineColor = Color(0xFF2A2A2A);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF7F7F7F);

  static const Color glassBackground = Color(0xCC121212);
  static const Color glassBorder = Color(0x28FFFFFF);
  static const Color glassShadow = Color(0x66000000);

  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF1DB954), Color(0xFF158A3E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Legacy text styles (Spotify) ─────────────────────────────────────────
  static TextStyle get technicalSm => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );
  static TextStyle get technicalXs => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );
  static TextStyle get headingLg => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );
  static TextStyle get headingMd => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );
  static TextStyle get headingSm => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );
  static TextStyle get bodyMd => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );
  static TextStyle get bodySm => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );
  static TextStyle get labelMd => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textSecondary,
    letterSpacing: 1.2,
  );

  // ── Legacy darkTheme (Spotify, kept for backward compat) ──────────────────
  static ThemeData get darkTheme => buildTheme(AppThemeMode.spotify);

  // ── Main builder ─────────────────────────────────────────────────────────
  static ThemeData buildTheme(AppThemeMode mode) {
    final t = ThemeVariants.of(mode);
    final brightness = t.isLight ? Brightness.light : Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: t.bgBase,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: t.accent,
        onPrimary: t.isLight ? Colors.white : Colors.black,
        secondary: t.accentDim,
        onSecondary: t.isLight ? Colors.white : Colors.black,
        surface: t.bgSurface,
        onSurface: t.textPrimary,
        error: const Color(0xFFCF6679),
        onError: Colors.white,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: t.textPrimary),
      ),

      textTheme: TextTheme(
        displayLarge: t.textStyle(32, FontWeight.w700, t.textPrimary),
        headlineMedium: t.textStyle(24, FontWeight.w700, t.textPrimary),
        titleLarge: t.textStyle(16, FontWeight.w700, t.textPrimary),
        bodyLarge: t.textStyle(15, FontWeight.w400, t.textPrimary),
        bodyMedium: t.textStyle(13, FontWeight.w400, t.textSecondary),
        bodySmall: t.textStyle(12, FontWeight.w400, t.textSecondary),
      ),

      sliderTheme: SliderThemeData(
        trackHeight: mode == AppThemeMode.neumorphic ? 6 : 4,
        activeTrackColor: t.accent,
        inactiveTrackColor: t.textPrimary.withOpacity(0.1),
        thumbColor: mode == AppThemeMode.zen ? t.accent : t.textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: mode == AppThemeMode.neumorphic ? 9 : 6,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: t.bgOverlay,
        selectedColor: t.accent,
        labelStyle: t.textStyle(13, FontWeight.w500, t.textPrimary),
        secondaryLabelStyle: t.textStyle(
          13,
          FontWeight.w500,
          t.isLight ? Colors.white : Colors.black,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.bgBase,
        selectedItemColor: t.accent,
        unselectedItemColor: t.textMuted,
        selectedLabelStyle: t.textStyle(11, FontWeight.w500, t.accent),
        unselectedLabelStyle: t.textStyle(11, FontWeight.w500, t.textMuted),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

// =============================================================================
// CupertinoClickable — press-scale feedback widget (unchanged)
// =============================================================================

class CupertinoClickable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;

  const CupertinoClickable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.97,
  });

  @override
  State<CupertinoClickable> createState() => _CupertinoClickableState();
}

class _CupertinoClickableState extends State<CupertinoClickable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.onTap != null ? _controller.forward() : null,
      onTapUp: (_) => widget.onTap != null ? _controller.reverse() : null,
      onTapCancel: () => widget.onTap != null ? _controller.reverse() : null,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}

// =============================================================================
// NeuBox — neumorphic container helper (used in Neumorphic theme screens)
// =============================================================================

class NeuBox extends StatelessWidget {
  final Widget child;
  final bool isPressed;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;

  const NeuBox({
    super.key,
    required this.child,
    this.isPressed = false,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final r = borderRadius ?? BorderRadius.circular(16);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgBase,
        borderRadius: r,
        boxShadow: isPressed
            ? [
                BoxShadow(
                  color: t.neuDark.withOpacity(0.6),
                  offset: const Offset(2, 2),
                  blurRadius: 6,
                ),
                BoxShadow(
                  color: t.neuLight,
                  offset: const Offset(-2, -2),
                  blurRadius: 6,
                ),
              ]
            : [
                BoxShadow(
                  color: t.neuDark.withOpacity(0.6),
                  offset: const Offset(6, 6),
                  blurRadius: 14,
                ),
                BoxShadow(
                  color: t.neuLight,
                  offset: const Offset(-6, -6),
                  blurRadius: 14,
                ),
              ],
      ),
      child: child,
    );
  }
}

// =============================================================================
// GlassBox — glassmorphism container helper (used in Frost theme screens)
// =============================================================================

class GlassBox extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;

  const GlassBox({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.glassBg,
          borderRadius: borderRadius ?? BorderRadius.circular(20),
          border: Border.all(color: t.glassBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              spreadRadius: -4,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
