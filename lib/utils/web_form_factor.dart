import 'package:flutter/foundation.dart';

import 'web_env.dart';

// =============================================================================
// web_form_factor.dart — phone or desktop UI in the browser.
//
// Native builds pick the UI by OS (PlatformUtils). A browser can be anything,
// so the web build decides from the user agent and the viewport width, and
// re-decides live when the window is resized or a phone is rotated:
//
//   * phone/tablet browsers (Android, iPhone, iPad, "Mobi") -> phone UI
//   * touch-only machines that claim a desktop UA (iPadOS Safari) -> phone UI
//   * desktop browsers narrower than [WebFormFactor.desktopMinWidth] -> phone UI
//   * everything else -> the Windows desktop UI
//
// A small hysteresis band stops the layout flapping while a window is dragged
// across the breakpoint.
// =============================================================================

enum FormFactor { phone, desktop }

abstract final class WebFormFactor {
  /// Viewport width (logical px) at which a desktop browser gets the desktop
  /// UI. Matches PlatformUtils.kDesktopBreakpoint.
  static const double desktopMinWidth = 800;

  /// Once in the desktop UI, stay there until the window is this narrow.
  static const double desktopExitWidth = 760;

  static final RegExp _mobileUa = RegExp(
    r'Android|iPhone|iPad|iPod|Mobile|Mobi|Opera Mini|IEMobile|Silk|webOS|BlackBerry',
    caseSensitive: false,
  );

  /// True when the user agent names a phone or tablet browser. iPadOS Safari
  /// reports a Mac UA, so a "Macintosh" with a touch screen counts too.
  static bool isMobileBrowser(BrowserInfo info) {
    if (_mobileUa.hasMatch(info.userAgent)) return true;
    final macTouch = info.userAgent.contains('Macintosh') && info.maxTouchPoints > 1;
    return macTouch;
  }

  /// The pure decision. [previous] adds hysteresis around the breakpoint.
  static FormFactor decide({
    required BrowserInfo info,
    required double viewportWidth,
    FormFactor? previous,
  }) {
    if (isMobileBrowser(info)) return FormFactor.phone;
    // Touch-only desktop UA (rare: some Chromebooks in tablet mode) -> phone.
    if (!info.finePointer && info.maxTouchPoints > 0) return FormFactor.phone;
    final threshold = previous == FormFactor.desktop ? desktopExitWidth : desktopMinWidth;
    return viewportWidth >= threshold ? FormFactor.desktop : FormFactor.phone;
  }

  static BrowserInfo? _info;

  /// Browser facts, read once (they don't change while the page is open,
  /// except the pointer, which [refresh] re-reads).
  static BrowserInfo get info => _info ??= readBrowserInfo() ?? const BrowserInfo();

  /// The current choice. Listen to rebuild when it changes.
  static final ValueNotifier<FormFactor> current = ValueNotifier(FormFactor.desktop);

  /// True when the primary pointer is touch (no hover; long-press menus).
  static bool get touchPrimary => !info.finePointer;

  /// Re-decides from [viewportWidth]. Called at start-up and on every resize.
  static void refresh(double viewportWidth) {
    _info = readBrowserInfo() ?? _info ?? const BrowserInfo();
    current.value = decide(info: info, viewportWidth: viewportWidth, previous: _decided ? current.value : null);
    _decided = true;
  }

  static bool _decided = false;

  @visibleForTesting
  static void debugReset({BrowserInfo? info, FormFactor initial = FormFactor.desktop}) {
    _info = info;
    _decided = false;
    current.value = initial;
  }
}
