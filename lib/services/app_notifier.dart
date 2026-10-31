import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';
import 'android_integration.dart';

/// The app's own notifications (not the media notification, which belongs to
/// audio_service). One channel per kind so each can be silenced separately in
/// Android's system settings.
enum NotifyChannel {
  downloads('navivibe_downloads'),
  updates('navivibe_updates'),
  social('navivibe_social');

  final String id;
  const NotifyChannel(this.id);
}

String downloadsText(int done, int total) {
  if (done == total) return total == 1 ? 'Your song is ready offline.' : 'All $total songs are ready offline.';
  return '$done of $total songs are ready offline. The rest failed.';
}

/// Posts a notification on Android (native channel) or Windows (toast).
/// Everything is best effort: a blocked permission, a missing shell or an
/// unsupported platform just means nothing is shown.
class AppNotifier {
  AppNotifier._();

  static bool get enabledPref {
    try {
      return HiveBoxes.prefs.get(HiveBoxes.kNotificationsEnabled) != false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool v) async {
    await HiveBoxes.prefs.put(HiveBoxes.kNotificationsEnabled, v);
    if (v) unawaited(prime());
  }

  // A notification is a courtesy: it must never fail the download or update
  // it announces (and the Hive boxes may not be open, as in tests).

  /// Whether the app is on screen. A notification for something the person is
  /// already looking at is noise.
  static bool Function() inForeground = () {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  };

  @visibleForTesting
  static bool shouldShow({required bool foreground, required bool enabled}) => enabled && !foreground;

  /// Asks for the Android 13+ permission while the app is on screen (the
  /// prompt can't show from the background). Call when the person does
  /// something that will later notify them: starting a download, turning
  /// notifications on, first playback. Asks once ever.
  static Future<void> prime() => AndroidIntegration.requestNotificationPermission();

  /// Shows a notification now. Returns whether anything was posted.
  static Future<bool> show(
    NotifyChannel channel, {
    required String title,
    required String body,
    int id = 1,
  }) async {
    try {
      if (!shouldShow(foreground: inForeground(), enabled: enabledPref)) return false;
      if (PlatformUtils.isAndroid) {
        return await AndroidIntegration.notify(channel: channel.id, id: id, title: title, body: body);
      }
      if (PlatformUtils.isWindows) return await _windowsToast(title, body);
    } catch (e) {
      debugPrint('[AppNotifier] ${channel.id} failed: $e');
    }
    return false;
  }

  // ── Windows ───────────────────────────────────────────────────────────────

  static const _aumid = 'NaviVibe';
  static bool _registered = false;

  /// Toasts need an app identity. Registering a display name under the
  /// current user's AppUserModelId key (no installer, no admin) makes Windows
  /// show "NaviVibe" with its icon and list it in Settings > Notifications.
  static Future<void> _registerWindowsApp() async {
    if (_registered) return;
    _registered = true;
    Future<void> put(String name, String value, [String type = 'REG_SZ']) => Process.run('reg', [
      'add', r'HKCU\Software\Classes\AppUserModelId\' + _aumid,
      '/v', name, '/t', type, '/d', value, '/f',
    ]);
    await put('DisplayName', 'NaviVibe');
    await put('ShowInSettings', '1', 'REG_DWORD');
    await put('IconUri', Platform.resolvedExecutable);
  }

  static Future<bool> _windowsToast(String title, String body) async {
    await _registerWindowsApp();
    final r = await Process.run('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
      '-EncodedCommand', encodeForPowerShell(windowsToastScript(title, body)),
    ]);
    if (r.exitCode != 0) debugPrint('[AppNotifier] toast failed: ${r.stderr}');
    return r.exitCode == 0;
  }

  @visibleForTesting
  static String xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// PowerShell that raises one toast. Text is XML-escaped, then placed in a
  /// single-quoted PowerShell string (quotes doubled), so no title or body can
  /// break out into code.
  @visibleForTesting
  static String windowsToastScript(String title, String body) {
    final xml = '<toast><visual><binding template="ToastGeneric">'
        '<text>${xmlEscape(title)}</text><text>${xmlEscape(body)}</text>'
        '</binding></visual></toast>';
    final literal = xml.replaceAll("'", "''");
    return r'''
$ErrorActionPreference = 'Stop'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml('''
        "'$literal'"
        r''')
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('NaviVibe').Show($toast)
''';
  }

  /// `-EncodedCommand` takes base64 of the UTF-16LE script.
  @visibleForTesting
  static String encodeForPowerShell(String script) {
    final bytes = <int>[for (final u in script.codeUnits) ...[u & 0xff, u >> 8]];
    return base64.encode(bytes);
  }
}
