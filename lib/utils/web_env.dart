// =============================================================================
// web_env.dart — what the browser says about the device (web build only).
//
// Native builds get the stub, which reports "not a browser". The web file reads
// navigator.userAgent, maxTouchPoints and the CSS pointer media query.
// =============================================================================

export 'web_env_stub.dart' if (dart.library.js_interop) 'web_env_web.dart';

/// A snapshot of the browser facts the form-factor choice depends on.
class BrowserInfo {
  /// `navigator.userAgent`, or empty when unknown.
  final String userAgent;

  /// `navigator.maxTouchPoints` (0 on mouse-only machines).
  final int maxTouchPoints;

  /// True when the primary pointer is precise (mouse, trackpad):
  /// CSS `(pointer: fine)`.
  final bool finePointer;

  const BrowserInfo({this.userAgent = '', this.maxTouchPoints = 0, this.finePointer = true});
}
