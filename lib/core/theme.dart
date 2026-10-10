import 'package:flutter/cupertino.dart'
    show CupertinoPageTransitionsBuilder, CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'album_palette.dart';

export 'album_palette.dart' show AlbumPalette;

// =============================================================================
// NaviVibe's design language is Apple Music on iPhone, built for Android.
//
// Colour: Apple's dark-mode system colours (pure black ground, #1C1C1E grouped
// surfaces, 60 % secondary labels, hairline separators) with one accent —
// system green. Album colour lives only on Now Playing and the mini player,
// which read [AppThemeTokens.palette] directly.
//
// Type: Apple's text styles (Large Title 34 … Caption 2 11), set in Inter /
// Inter Display — the closest licensed match to SF Pro, which can't ship on
// Android.
//
// Widgets read everything through `ThemeTokens.of(context)` plus the [Space],
// [Radii] and [Motion] constants below; screens never hardcode a colour, a
// font size or a corner radius.
// =============================================================================

/// Spacing scale (pt). Apple's layout margins are 16 on iPhone, 20 on wide.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Leading/trailing page margin.
  static const double gutter = 16;

  /// Clearance for content scrolling under the floating mini player + tab bar.
  static const double playerClearance = 152;
}

/// Corner radii, matched to the iOS role of each surface.
abstract final class Radii {
  /// Track thumbnails in rows.
  static const double thumb = 4;

  /// Album / playlist covers in grids and shelves.
  static const double cover = 6;

  /// Hero artwork on album and playlist pages.
  static const double hero = 10;

  /// Buttons, search field, grouped list sections.
  static const double control = 10;

  /// Inset grouped list sections (Settings, Library).
  static const double group = 12;

  /// Sheets and the floating mini player.
  static const double sheet = 16;
}

/// Motion durations and curves. iOS motion is quick and decelerates hard.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

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

  /// Apple's dark-mode systemGreen — the app's single accent.
  static const Color brandGreen = Color(0xFF30D158);

  /// App chrome is Apple's neutral dark system palette whatever is playing.
  /// Album colour belongs to Now Playing and the mini player only (they read
  /// [palette] directly); tinting every page per song made the app purple or
  /// pink and a different app with each track.
  factory AppThemeTokens.fromPalette(AlbumPalette p) {
    return AppThemeTokens._(
      palette: p,
      bgBase: const Color(0xFF000000), // systemBackground
      bgSurface: const Color(0xFF1C1C1E), // secondarySystemBackground
      bgElevated: const Color(0xFF2C2C2E), // tertiarySystemBackground
      bgOverlay: const Color(0xFF3A3A3C), // systemGray5 — pressed / chips
      accent: brandGreen,
      accentDim: const Color(0xFF248A3D), // systemGreen, accessible dark
      onAccent: const Color(0xFF000000),
      gold: const Color(0xFFFFD60A), // systemYellow
      textPrimary: const Color(0xFFFFFFFF), // label
      textSecondary: const Color(0x99EBEBF5), // secondaryLabel (60 %)
      textMuted: const Color(0x4DEBEBF5), // tertiaryLabel (30 %)
      outline: const Color(0xA6545458), // separator
    );
  }

  static final AppThemeTokens fallback =
      AppThemeTokens.fromPalette(AlbumPalette.fallback);

  // ── Typography: Apple's text styles ───────────────────────────────────────
  // Use these named styles; `.copyWith(color: …)` for a different colour.
  TextStyle get largeTitle => naviText(34, FontWeight.w700, textPrimary, height: 41 / 34);
  TextStyle get title1 => naviText(28, FontWeight.w700, textPrimary, height: 34 / 28);
  TextStyle get title2 => naviText(22, FontWeight.w700, textPrimary, height: 28 / 22);
  TextStyle get title3 => naviText(20, FontWeight.w600, textPrimary, height: 25 / 20);
  TextStyle get headline => naviText(17, FontWeight.w600, textPrimary, height: 22 / 17);
  TextStyle get body => naviText(17, FontWeight.w400, textPrimary, height: 22 / 17);
  TextStyle get callout => naviText(16, FontWeight.w400, textPrimary, height: 21 / 16);
  TextStyle get subheadline => naviText(15, FontWeight.w400, textSecondary, height: 20 / 15);
  TextStyle get footnote => naviText(13, FontWeight.w400, textSecondary, height: 18 / 13);
  TextStyle get caption1 => naviText(12, FontWeight.w400, textSecondary, height: 16 / 12);
  TextStyle get caption2 => naviText(11, FontWeight.w500, textSecondary, height: 13 / 11);

  /// Escape hatch for one-off display sizes (hero numbers, desktop titles).
  TextStyle textStyle(double size, FontWeight weight, Color color) =>
      naviText(size, weight, color);

  /// Always opaque — safe for menus and dialogs over moving content.
  Color get bgSurfaceOpaque => Color.alphaBlend(bgSurface, bgBase);

  /// iOS tertiarySystemFill — search fields, secondary buttons.
  Color get fill => const Color(0x3D767680);

  /// Opaque hairline for places a translucent separator would double up.
  Color get separatorOpaque => const Color(0xFF38383A);

  // ── Semantic state colours (iOS system colours, dark) ─────────────────────
  Color get positive => brandGreen;
  Color get warning => const Color(0xFFFF9F0A); // systemOrange
  Color get danger => const Color(0xFFFF453A); // systemRed

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

  /// Material widgets themed to read as their iOS counterparts.
  static ThemeData build(AppThemeTokens t) {
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control));
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
        secondary: t.accent,
        onSecondary: t.onAccent,
        surface: t.bgSurface,
        onSurface: t.textPrimary,
        surfaceContainerHighest: t.bgElevated,
        outline: t.outline,
        error: t.danger,
        onError: t.textPrimary,
      ),
      // iOS has no ink ripples: presses dim or scale instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: t.textPrimary.withValues(alpha: 0.05),
      focusColor: t.accent.withValues(alpha: 0.24),
      cupertinoOverrideTheme: cupertino(t),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.32),
        selectionHandleColor: t.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: t.headline,
        iconTheme: IconThemeData(color: t.accent),
        actionsIconTheme: IconThemeData(color: t.accent),
      ),
      textTheme: TextTheme(
        displayLarge: t.largeTitle,
        headlineLarge: t.title1,
        headlineMedium: t.title2,
        headlineSmall: t.title3,
        titleLarge: t.headline,
        titleMedium: t.headline,
        titleSmall: t.subheadline,
        bodyLarge: t.body,
        bodyMedium: t.callout,
        bodySmall: t.footnote,
        labelLarge: t.headline,
        labelMedium: t.footnote,
        labelSmall: t.caption2,
      ),
      iconTheme: IconThemeData(color: t.textPrimary, size: 24),
      dividerTheme: DividerThemeData(color: t.outline, thickness: 0.5, space: 0.5),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.textPrimary,
        inactiveTrackColor: t.fill,
        thumbColor: t.textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(t.textPrimary),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.bgOverlay,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          minimumSize: const Size(0, 50),
          shape: control,
          textStyle: t.headline,
          padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.accent,
          backgroundColor: t.fill,
          minimumSize: const Size(0, 50),
          side: BorderSide.none,
          shape: control,
          textStyle: t.headline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: t.accent, textStyle: t.body),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.accent, highlightColor: Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.bgElevated,
        contentTextStyle: t.subheadline.copyWith(color: t.textPrimary),
        actionTextColor: t.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.group)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.bgSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.bgSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
        showDragHandle: true,
        dragHandleColor: t.textMuted,
        dragHandleSize: const Size(36, 5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: t.headline,
        contentTextStyle: t.footnote.copyWith(color: t.textPrimary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.group)),
        textStyle: t.body,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.accent,
        textColor: t.textPrimary,
        titleTextStyle: t.body,
        subtitleTextStyle: t.subheadline,
        minVerticalPadding: Space.sm,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.textSecondary,
        linearTrackColor: t.fill,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(t.textMuted),
        radius: const Radius.circular(3),
        thickness: WidgetStateProperty.all(3),
      ),
      // iOS navigation everywhere: slide in from the right, swipe the left
      // edge to go back — on Android too.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Theme for the Cupertino widgets the app uses (nav bars, switches,
  /// segmented controls, action sheets) so they share the same type and green.
  static CupertinoThemeData cupertino(AppThemeTokens t) => CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: t.accent,
        primaryContrastingColor: t.onAccent,
        scaffoldBackgroundColor: t.bgBase,
        barBackgroundColor: t.bgBase.withValues(alpha: 0.75),
        textTheme: CupertinoTextThemeData(
          primaryColor: t.accent,
          textStyle: t.body,
          actionTextStyle: t.body.copyWith(color: t.accent),
          navTitleTextStyle: t.headline,
          navLargeTitleTextStyle: t.largeTitle,
          navActionTextStyle: t.body.copyWith(color: t.accent),
          tabLabelTextStyle: t.caption2,
        ),
      );
}

/// iOS scroll feel app-wide: rubber-band overscroll, no Android glow, mouse
/// and trackpad drag enabled on desktop.
class NaviScrollBehavior extends MaterialScrollBehavior {
  const NaviScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
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
