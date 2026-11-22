import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// smtc_windows 1.1.0 only starts under the flutter_rust_bridge it was generated with
/// (2.11.1). Under another version `SMTCWindows.initialize()` throws "codegen version should be
/// the same as runtime version", the app silently has no Windows media session, and the touchpad
/// tap, media keys and volume flyout never reach it. Found on the profile build, 22 Nov 2026.
void main() {
  test('flutter_rust_bridge stays at the version smtc_windows was generated with', () {
    final lock = File('pubspec.lock').readAsStringSync().replaceAll('\r\n', '\n');
    final m = RegExp(r'\n  flutter_rust_bridge:\n(?:    .*\n)*?    version: "([^"]+)"').firstMatch(lock);
    expect(m, isNotNull, reason: 'flutter_rust_bridge is no longer in pubspec.lock');
    expect(m!.group(1), '2.11.1',
        reason: 'upgrade smtc_windows and this pin together, then run the app and check '
            '"[SMTC] unavailable" is not in its output');
  });
}
