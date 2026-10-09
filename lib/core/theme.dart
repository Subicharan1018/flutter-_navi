import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'album_palette.dart';

export 'album_palette.dart' show AlbumPalette;

// =============================================================================
// NaviVibe has ONE theme, and it is alive: every colour role is derived from
// the album that is playing. The ground is near-black tinted with the cover's
// deep tone; the accent is the cover's vibrant tone, contrast-corrected.
//
// Widgets read tokens through `ThemeTokens.of(context)` and never hardcode
// colours, so the whole app re-tints when the song changes.
// =============================================================================

/// Size-specific tracking (Apple's tracking tables, translated to Inter):
/// small text opens up slightly, display text tightens.
double trackingFor(double size) {
  if (size <= 11) return size * 0.01;
  if (size <= 13) return 0;
  if (size <= 17) return size * -0.008;
  if (size <= 24) return size * -0.016;
  if (size <= 34) return size * -0.022;
  return size * -0.028;
}

/// Inter for text sizes, Inter Display (the optical cut drawn for large
/// sizes) from 20pt up — the same switch SF makes between Text and Display.
TextStyle naviText(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
  bool tabular = false,
}) {
  final display = size >= 20 && weight.value >= 500;
  return TextStyle(
    fontFamily: display ? 'InterDisplay' : 'Inter',
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: trackingFor(size),
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

class AppThemeTokens {
  /// The palette these tokens were derived from.
  final AlbumPalette palette;

  // ── Grounds (darkest → brightest), tinted by the playing album ─────────────
  final Color bgBase; // scaffold / page background
  final Color bgSurface; // cards, sheets, rows on hover
  final Color bgElevated; // popovers, menus, raised rows
  final Color bgOverlay; // chips, scrims, pressed fills

  // ── Accent (the album's vibrant tone) ─────────────────────────────────────
  final Color accent;
  final Color accentDim;
  final Color onAccent;
  final Color gold; // ratings / stars — warm, independent of the album

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Hairlines ─────────────────────────────────────────────────────────────
  final Color outline;

  const AppThemeTokens._({
    required this.palette,
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgOverlay,
    required this.accent,
    required this.accentDim,
    required this.onAccent,
    required this.gold,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.outline,
  });

  factory AppThemeTokens.fromPalette(AlbumPalette p) {
    Color tint(Color ground, double amount) => Color.lerp(ground, p.deep, amount)!;
    return AppThemeTokens._(
      palette: p,
      bgBase: tint(const Color(0xFF000000), 0.55),
      bgSurface: tint(const Color(0xFF111111), 0.45),
      bgElevated: tint(const Color(0xFF1B1B1B), 0.40),
      bgOverlay: tint(const Color(0xFF2A2A2A), 0.35),
      accent: p.vibrant,
      accentDim: Color.lerp(p.vibrant, p.deep, 0.45)!,
      onAccent: p.onVibrant,
      gold: const Color(0xFFFFC94D),
      textPrimary: const Color(0xFFFFFFFF),
      textSecondary: const Color(0xA8FFFFFF), // 66%
      textMuted: const Color(0x70FFFFFF), // 44%
      outline: const Color(0x14FFFFFF),
    );
  }

  static final AppThemeTokens fallback =
      AppThemeTokens.fromPalette(AlbumPalette.fallback);

  // ── Typography ────────────────────────────────────────────────────────────
  TextStyle textStyle(double size, FontWeight weight, Color color) =>
      naviText(size, weight, color);

  TextStyle get headingLg => naviText(28, FontWeight.w800, textPrimary);
  TextStyle get headingMd => naviText(22, FontWeight.w700, textPrimary);
  TextStyle get headingSm => naviText(16, FontWeight.w700, textPrimary);
  TextStyle get bodyMd => naviText(14, FontWeight.w400, textPrimary);
  TextStyle get bodySm => naviText(12, FontWeight.w400, textSecondary);
  TextStyle get labelMd => naviText(11, FontWeight.w600, textSecondary);
  TextStyle get technicalSm => naviText(14, FontWeight.w500, textSecondary, tabular: true);
  TextStyle get technicalXs => naviText(12, FontWeight.w400, textMuted, tabular: true);

  /// Always opaque — safe for menus and dialogs over moving content.
  Color get bgSurfaceOpaque => Color.alphaBlend(bgSurface, bgBase);

  // ── Semantic state colours ────────────────────────────────────────────────
  Color get positive => const Color(0xFF3DDC84);
  Color get warning => gold;
  Color get danger => const Color(0xFFFF5D73);

  @override
  bool operator ==(Object other) =>
      other is AppThemeTokens && other.palette == palette;

  @override
  int get hashCode => palette.hashCode;
}

/// Exposes the live [AppThemeTokens] to the tree.
class ThemeTokens extends InheritedWidget {
  final AppThemeTokens tokens;

  const ThemeTokens({super.key, required this.tokens, required super.child});

  static AppThemeTokens of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<ThemeTokens>();
    return w?.tokens ?? AppThemeTokens.fallback;
  }

  @override
  bool updateShouldNotify(ThemeTokens old) => old.tokens != tokens;
}

class AppTheme {
  AppTheme._();

  static ThemeData build(AppThemeTokens t) {
    TextStyle s(double size, FontWeight w, Color c) => naviText(size, w, c);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: t.bgBase,
      canvasColor: t.bgBase,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: t.accent,
        onPrimary: t.onAccent,
        secondary: t.palette.glow,
        onSecondary: const Color(0xFF0B0B0B),
        surface: t.bgSurfaceOpaque,
        onSurface: t.textPrimary,
        surfaceContainerHighest: t.bgElevated,
        outline: t.outline,
        error: t.danger,
        onError: Colors.white,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: t.textPrimary.withValues(alpha: 0.05),
      focusColor: t.accent.withValues(alpha: 0.24),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.32),
        selectionHandleColor: t.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: s(20, FontWeight.w700, t.textPrimary),
        iconTheme: IconThemeData(color: t.textPrimary),
      ),
      textTheme: TextTheme(
        displayLarge: s(32, FontWeight.w800, t.textPrimary),
        headlineMedium: s(24, FontWeight.w700, t.textPrimary),
        titleLarge: s(18, FontWeight.w700, t.textPrimary),
        titleMedium: s(16, FontWeight.w600, t.textPrimary),
        bodyLarge: s(15, FontWeight.w400, t.textPrimary),
        bodyMedium: s(14, FontWeight.w400, t.textSecondary),
        bodySmall: s(12, FontWeight.w400, t.textSecondary),
        labelLarge: s(14, FontWeight.w600, t.textPrimary),
        labelSmall: s(11, FontWeight.w600, t.textSecondary),
      ),
      iconTheme: IconThemeData(color: t.textPrimary, size: 24),
      dividerTheme: DividerThemeData(color: t.outline, thickness: 1, space: 1),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.accent,
        inactiveTrackColor: t.textPrimary.withValues(alpha: 0.14),
        thumbColor: t.textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.bgOverlay,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.bgOverlay,
        selectedColor: t.accent,
        labelStyle: s(13, FontWeight.w600, t.textPrimary),
        secondaryLabelStyle: s(13, FontWeight.w600, t.onAccent),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          shape: const StadiumBorder(),
          textStyle: s(15, FontWeight.w700, t.onAccent),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          textStyle: s(14, FontWeight.w600, t.accent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.bgElevated,
        contentTextStyle: s(14, FontWeight.w500, t.textPrimary),
        actionTextColor: t.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.bgElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.bgElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: t.textMuted,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: s(19, FontWeight.w700, t.textPrimary),
        contentTextStyle: s(14, FontWeight.w400, t.textSecondary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: s(14, FontWeight.w500, t.textPrimary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        titleTextStyle: s(15, FontWeight.w500, t.textPrimary),
        subtitleTextStyle: s(13, FontWeight.w400, t.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.bgOverlay,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(t.textPrimary.withValues(alpha: 0.22)),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// =============================================================================
// PressScale — tactile press feedback. Scales on pointer-DOWN (instant
// response), springs back on release; a press never waits for the tap to
// resolve.
// =============================================================================

class CupertinoClickable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final String? semanticLabel;

  const CupertinoClickable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 0.96,
    this.semanticLabel,
  });

  @override
  State<CupertinoClickable> createState() => _CupertinoClickableState();
}

class _CupertinoClickableState extends State<CupertinoClickable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: widget.scaleFactor,
  ).animate(CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeOutBack,
  ));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _c.forward() : null,
        onTapUp: _enabled ? (_) => _c.reverse() : null,
        onTapCancel: _enabled ? () => _c.reverse() : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
