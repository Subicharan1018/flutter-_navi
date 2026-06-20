import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// =============================================================================
// platform_utils.dart — Centralised platform detection
//
// Pure static utility — ZERO provider dependencies by design.
// Every platform-conditional branch in the app should use this instead of
// scattering `Platform.isLinux` / `Platform.isAndroid` checks everywhere.
//
// Usage:
//   if (PlatformUtils.isDesktop) { ... }
//   if (PlatformUtils.isLinux)   { ... }
// =============================================================================

abstract final class PlatformUtils {
  /// True on Linux, Windows, and macOS — i.e. any desktop OS.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// True only on Linux.
  static bool get isLinux =>
      !kIsWeb && Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST');

  /// True only on Windows.
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// True only on macOS.
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// True on Android and iOS.
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True only on Android.
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// True only on iOS.
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// True when running in a browser via Flutter Web.
  static bool get isWeb => kIsWeb;

  // ── Feature capability flags ────────────────────────────────────────────────

  /// True when the platform supports keyboard shortcut handling.
  /// Alias for [isDesktop] — kept as a named flag so intent is explicit
  /// at call sites (e.g. wrapping a `CallbackShortcuts` widget).
  static bool get supportsKeyboardShortcuts => isDesktop;

  /// True when MPRIS D-Bus media control is available.
  /// Only the Linux platform exposes MPRIS.
  static bool get supportsMpris => isLinux;

  /// True when the OS supports window management APIs (size, position, title).
  /// Available on all desktop platforms via the `window_manager` package.
  static bool get supportsWindowManager => isDesktop;

  /// True when the options menu should render as a popup rather than a
  /// bottom sheet. Bottom sheets feel unnatural with a mouse cursor.
  static bool get prefersPopupMenu => isDesktop;

  /// True when the dialog should be a centered overlay rather than a
  /// modal bottom sheet (e.g. AddToPlaylistDialog, EditPlaylistScreen).
  static bool get prefersCenteredDialogs => isDesktop;

  /// True when the layout should render an expanded sidebar (NavigationRail)
  /// rather than a bottom navigation bar.
  /// Drive this from a LayoutBuilder width check AND this flag so the layout
  /// also adapts when a desktop window is narrowed below [kDesktopBreakpoint].
  static bool get prefersSidebarNavigation => isDesktop;

  /// Minimum window width (logical pixels) at which the sidebar is shown.
  /// Below this threshold, bottom navigation is used even on desktop.
  static const double kDesktopBreakpoint = 800.0;

  /// Minimum window width (logical pixels) at which the Now Playing screen
  /// renders as a persistent right-side panel instead of a full-screen push.
  static const double kWideScreenBreakpoint = 1200.0;

  /// Alias for [isDesktop] — used in now_playing_screen layout logic.
  static bool get isWideScreen => isDesktop;

  // ── XDG / filesystem helpers (Linux-only) ──────────────────────────────────

  /// Returns the XDG Downloads directory path, if available.
  /// Returns null on non-Linux platforms or when the env var is unset.
  static String? get xdgDownloadDir {
    if (!isLinux) return null;
    final xdg = Platform.environment['XDG_DOWNLOAD_DIR'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return '$home/Downloads';
    return null;
  }

  /// Returns the user's home directory, if available.
  static String? get homeDir {
    if (kIsWeb) return null;
    return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  }
}
