import 'package:flutter/cupertino.dart'
    show CupertinoPageTransitionsBuilder, CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'album_palette.dart';

export 'album_palette.dart' show AlbumPalette;

// =============================================================================
// NaviVibe's design language is Apple Music on iPhone, built for Android.
//
// Colour: Apple's dark-mode roles (ground, grouped surface, elevated, overlay,
// secondary / tertiary labels, separators) on an AMOLED black ground, in
// monochrome: the one accent is white (black text on it). Every role is
// opaque; only artwork fades into its page. Collection pages take their
// ground from the cover ([AppThemeTokens.tinted]).
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
  static const double thumb = 5;

  /// Album / playlist covers in grids and shelves.
  static const double cover = 8;

  /// Hero artwork on album and playlist pages.
  static const double hero = 12;

  /// Buttons, search field.
  static const double control = 12;

  /// Fully rounded ends (capsule buttons, tab bar, mini player).
  static const double capsule = 999;

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

  /// Apple's spring, specified as a perceptual [duration] (seconds) and a
  /// [bounce] (0 = critically damped, no overshoot; keep under ~0.4 in UI),
  /// converted exactly as WWDC23 "Animate with springs" defines it:
  /// mass 1, stiffness (2π/duration)², damping 4π(1−bounce)/duration for
  /// bounce ≥ 0, else 4π/(duration·(1+bounce)). Unlike a curve, a spring
  /// starts from the current velocity, so interrupted motion never jerks.
  static SpringDescription appleSpring(double duration, {double bounce = 0}) {
    final stiffness = math.pow(2 * math.pi / duration, 2).toDouble();
    final damping = bounce >= 0
        ? 4 * math.pi * (1 - bounce) / duration
        : 4 * math.pi / (duration * (1 + bounce));
    return SpringDescription(mass: 1, stiffness: stiffness, damping: damping);
  }

  /// The cover growing when music starts and receding on pause: a gentle
  /// landing (Apple's default `.spring` feel with a touch of bounce).
  static final SpringDescription cover = appleSpring(0.5, bounce: 0.15);

  /// Covers moving along the deck (swipe release and skips): quick, settled.
  static final SpringDescription deck = appleSpring(0.38, bounce: 0.06);

  /// The cover-to-header flight when Lyrics or the Queue open: smooth, no
  /// overshoot, so the header never overshoots its slot.
  static final SpringDescription flight = appleSpring(0.5);
}

/// Inter's published "dynamic metrics" tracking curve (rsms.me/inter/dynmetrics):
/// em = a + b·e^(c·size). Small text opens slightly, display text tightens —
/// the same behaviour as SF's size-specific tracking, but correct for Inter's
/// wider letterforms.
double trackingFor(double size) => size * (-0.0223 + 0.185 * math.exp(-0.1745 * size));

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

  // ── Accent (monochrome: white, with a grey for secondary marks) ───────────
  final Color accent;
  final Color accentDim;
  final Color onAccent;
  final Color gold; // ratings / stars — warm, independent of the album

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Hairlines and fills ───────────────────────────────────────────────────
  final Color outline;

  /// iOS tertiarySystemFill — search fields, secondary buttons, tracks.
  final Color fill;

  /// True inside an artwork-coloured page (see [AppThemeTokens.tinted]).
  final bool tinted;

  const AppThemeTokens._({
    this.fill = const Color(0xFF1C1C1E),
    this.tinted = false,
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

  /// The app's single accent. Monochrome: white on the black chrome; things
  /// filled with it put [onAccent] (black) on top.
  static const Color brandAccent = Color(0xFFFFFFFF);

  /// Secondary marks next to the accent (dim chart bars, the second swipe
  /// action) — systemGray2, so white still leads.
  static const Color brandAccentDim = Color(0xFF636366);

  /// Fill behind Settings-style row glyphs: one neutral tile for every row
  /// (monochrome — no per-row colours).
  static const Color iconTile = Color(0xFF2C2C2E);

  /// App chrome stays AMOLED black whatever is playing. Album
  /// colour belongs to Now Playing, the mini player (they read [palette]
  /// directly) and collection pages ([AppThemeTokens.tinted]); tinting
  /// every page per song made the app a different app with each track.
  factory AppThemeTokens.fromPalette(AlbumPalette p) {
    return AppThemeTokens._(
      palette: p,
      bgBase: const Color(0xFF000000), // AMOLED black
      bgSurface: const Color(0xFF111111), // secondarySystemBackground
      bgElevated: const Color(0xFF1C1C1E), // tertiarySystemBackground
      bgOverlay: const Color(0xFF2C2C2E), // pressed fills, chips
      accent: brandAccent,
      accentDim: brandAccentDim,
      onAccent: const Color(0xFF000000),
      gold: const Color(0xFFFFD60A), // systemYellow
      textPrimary: const Color(0xFFFFFFFF), // label
      textSecondary: const Color(0xFF9E9EA4), // secondaryLabel, ≥ 6:1 on every ground
      textMuted: const Color(0xFF86868C), // tertiaryLabel, ≥ 4.5:1 up to bgElevated
      outline: const Color(0xFF262628), // separator
    );
  }

  static final AppThemeTokens fallback =
      AppThemeTokens.fromPalette(AlbumPalette.fallback);

  /// Tokens for a page painted in an artwork colour ([ground]). As in
  /// Apple Music's iOS 26 album pages, foreground is only ever white: the
  /// accent becomes white, secondary text and hairlines become white at
  /// reduced strength, and raised surfaces are lighter steps of the ground.
  factory AppThemeTokens.tinted(AlbumPalette p, Color ground) {
    // Every role is resolved to a solid colour against the ground.
    Color lift(double amount) => Color.lerp(ground, Colors.white, amount)!;
    return AppThemeTokens._(
      palette: p,
      tinted: true,
      bgBase: ground,
      bgSurface: lift(0.07),
      bgElevated: lift(0.12),
      bgOverlay: lift(0.18),
      accent: Colors.white,
      accentDim: lift(0.55),
      onAccent: Colors.black,
      gold: const Color(0xFFFFD60A),
      textPrimary: Colors.white,
      textSecondary: lift(0.68),
      textMuted: lift(0.55), // ≥ 4.5:1 on every clamped ground lightness
      outline: lift(0.14),
      fill: lift(0.12),
    );
  }

  // ── Typography: Apple's text styles, optically matched ────────────────────
  // Inter draws ~6 % larger and heavier than SF Pro at the same point size,
  // so each role is set one notch down (and Bold only for the Large Title)
  // to *look* like Apple's 34/28/22/20/17/16/15/13/12/11 scale on screen.
  // Use these named styles; `.copyWith(color: …)` for a different colour.
  TextStyle get largeTitle => naviText(32, FontWeight.w700, textPrimary, height: 1.18);
  TextStyle get title1 => naviText(26, FontWeight.w700, textPrimary, height: 1.2);
  TextStyle get title2 => naviText(21, FontWeight.w600, textPrimary, height: 1.25);
  TextStyle get title3 => naviText(19, FontWeight.w600, textPrimary, height: 1.25);
  TextStyle get headline => naviText(16, FontWeight.w600, textPrimary, height: 1.3);
  TextStyle get body => naviText(16, FontWeight.w400, textPrimary, height: 1.3);
  TextStyle get callout => naviText(15, FontWeight.w400, textPrimary, height: 1.3);
  TextStyle get subheadline => naviText(14, FontWeight.w400, textSecondary, height: 1.3);
  TextStyle get footnote => naviText(12.5, FontWeight.w400, textSecondary, height: 1.3);
  TextStyle get caption1 => naviText(11.5, FontWeight.w400, textSecondary, height: 1.3);
  TextStyle get caption2 => naviText(10.5, FontWeight.w500, textSecondary, height: 1.25);

  /// Escape hatch for one-off display sizes (hero numbers, desktop titles).
  TextStyle textStyle(double size, FontWeight weight, Color color) =>
      naviText(size, weight, color);

  /// Always opaque — safe for menus and dialogs over moving content.
  Color get bgSurfaceOpaque => Color.alphaBlend(bgSurface, bgBase);

  /// Opaque hairline for places a translucent separator would double up.
  Color get separatorOpaque => outline;

  // ── Semantic state colours ────────────────────────────────────────────────
  // Monochrome: success is plain white. Only warnings and destructive /
  // failure states keep a hue (iOS orange / red), because they must stand out.
  Color get positive => textPrimary;
  Color get warning => const Color(0xFFFF9F0A); // systemOrange
  Color get danger => const Color(0xFFFF453A); // systemRed

  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemRed = Color(0xFFFF453A);
  static const Color systemYellow = Color(0xFFFFD60A);
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFF636366);

  @override
  bool operator ==(Object other) =>
      other is AppThemeTokens && other.palette == palette && other.bgBase == bgBase && other.tinted == tinted;

  @override
  int get hashCode => Object.hash(palette, bgBase, tinted);
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
        barBackgroundColor: t.bgBase,
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
