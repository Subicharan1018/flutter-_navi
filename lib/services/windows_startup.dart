import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/platform_utils.dart';

// =============================================================================
// windows_startup.dart — "Start with Windows".
//
// Adds or removes NaviVibe's value under the per-user Run key
// (HKCU\Software\Microsoft\Windows\CurrentVersion\Run). No admin rights, no
// native plugin: the `reg` tool ships with Windows. The registered command
// carries [minimizedFlag], so a login launch opens straight into the tray.
// =============================================================================

/// Runs `reg.exe`. Replaced by a fake in tests.
typedef RegRunner = Future<ProcessResult> Function(List<String> args);

class WindowsStartup {
  WindowsStartup({RegRunner? run, String? executable}) : _run = run ?? _reg, _exe = executable;

  static final WindowsStartup instance = WindowsStartup();

  /// Passed to the app by the Run entry: start hidden in the tray.
  static const minimizedFlag = '--minimized';

  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _value = 'NaviVibe';

  final RegRunner _run;
  final String? _exe;

  static Future<ProcessResult> _reg(List<String> args) => Process.run('reg', args);

  static bool get supported => PlatformUtils.isWindows;

  /// The command stored in the registry: the quoted exe plus [minimizedFlag].
  String get command => '"${_exe ?? Platform.resolvedExecutable}" $minimizedFlag';

  /// Whether a launch with these arguments should stay hidden in the tray.
  static bool startsMinimized(List<String> args) => args.contains(minimizedFlag);

  Future<bool> isEnabled() async {
    try {
      final r = await _run(['query', _key, '/v', _value]);
      return r.exitCode == 0;
    } catch (e) {
      debugPrint('[Startup] query failed: $e');
      return false;
    }
  }

  /// Returns whether the registry now matches [enabled]; false means it could
  /// not be changed (the toggle should snap back).
  Future<bool> setEnabled(bool enabled) async {
    try {
      final r = enabled
          ? await _run(['add', _key, '/v', _value, '/t', 'REG_SZ', '/d', command, '/f'])
          : await _run(['delete', _key, '/v', _value, '/f']);
      if (r.exitCode == 0) return true;
      // Removing a value that was never there is already the wanted state.
      return !enabled && !await isEnabled();
    } catch (e) {
      debugPrint('[Startup] ${enabled ? 'enable' : 'disable'} failed: $e');
      return false;
    }
  }
}
