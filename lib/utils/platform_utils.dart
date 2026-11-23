import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

import 'web_form_factor.dart';

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
  /// Test seam: render the phone (false) or desktop (true) layout regardless
  /// of the host OS, so phone screens can be checked on a desktop test host.
  @visibleForTesting
  static bool? debugDesktopOverride;

  /// Test seam: pretend to run on an Android TV (true) or not (false).
  @visibleForTesting
  static bool? debugTvOverride;

  static bool _television = false;
  static const MethodChannel _android = MethodChannel('com.navivibe/android');

  /// True on Android TV / Google TV (leanback). Asked of the platform once at
  /// startup by [detectTelevision]; false everywhere else.
  static bool get isTv => debugTvOverride ?? _television;

  /// Asks Android whether this device is a television. Safe on any platform:
  /// a missing channel or any error means "not a TV".
  static Future<void> detectTelevision() async {
    if (!isAndroid) return;
    try {
      _television = await _android.invokeMethod<bool>('isTelevision') ?? false;
    } catch (_) {
      _television = false;
    }
    try {
      _lowRam = await _android.invokeMethod<bool>('isLowRam') ?? false;
    } catch (_) {
      _lowRam = false;
    }
  }

  /// Test seam: pretend the device is (true) or isn't (false) a low-RAM Android.
  @visibleForTesting
  static bool? debugLowRamOverride;

  static bool _lowRam = false;

  /// True when Android flags the device as low-RAM (`ActivityManager
  /// .isLowRamDevice`, roughly 1 GB or less). Set by [detectTelevision].
  static bool get isLowRam => debugLowRamOverride ?? _lowRam;

  /// True on a device that should spend less: a TV or a low-RAM phone.
  static bool get isConstrained => isTv || isLowRam;

  /// True when focus (D-pad, keyboard Tab) is the primary way to navigate,
  /// so focus rings and focus-friendly layouts matter most.
  static bool get isFocusFirst => isTv || isDesktop;

  /// True when the desktop UI is shown: on Linux, Windows and macOS, and in a
  /// desktop browser whose window is wide enough ([WebFormFactor]). This is a
  /// layout flag; for OS shell features (window, tray, hotkeys) use
  /// [isNativeDesktop].
  static bool get isDesktop =>
      debugDesktopOverride ?? (kIsWeb ? WebFormFactor.current.value == FormFactor.desktop : isNativeDesktop);

  /// True on a desktop OS build (not a browser): window manager, tray, global
  /// hotkeys, mini-player window and the like exist only here.
  static bool get isNativeDesktop => !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// True in a browser whose primary pointer is touch (no hover).
  static bool get isTouchWeb => kIsWeb && WebFormFactor.touchPrimary;

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

  /// True when the OS supports window management APIs (size, position, title).
  /// Available on native desktop platforms via the `window_manager` package;
  /// never in a browser, even when it shows the desktop UI.
  static bool get supportsWindowManager => isNativeDesktop;

  /// True when downloads, offline files and the local music library exist.
  /// The browser build streams only.
  static bool get supportsOfflineFiles => !kIsWeb;

  /// True when "Identify a song" can record (it records to a temp file).
  static bool get supportsSongRecognition => !kIsWeb;

  /// True when the app can update itself (Android APK, Windows installer).
  static bool get supportsSelfUpdate => isAndroid || isWindows;

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

  /// Content width at which wide two-column content layouts (replay, song
  /// rows with extra columns) switch on inside the sidebar shell.
  static const double kWideContentBreakpoint = 1100.0;

  /// Window width at which Now Playing splits artwork and queue side by side
  /// (landscape only).
  static const double kNowPlayingSplitBreakpoint = 900.0;

  /// Shortest side (logical pixels) from which a touch device counts as a
  /// tablet and gets the sidebar shell.
  static const double kTabletShortestSide = 600.0;

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
}
