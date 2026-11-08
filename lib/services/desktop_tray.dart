import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// desktop_tray.dart — Windows notification-area icon with transport controls.
//
// Left-click shows the window; right-click opens Play/Pause, Next, Previous,
// Show and Quit. While music plays, closing the window hides it to the tray
// instead of ending the app (setting, default on); Quit really exits.
// =============================================================================

class PlaybackTransport {
  final VoidCallback playPause;
  final VoidCallback next;
  final VoidCallback previous;
  final bool Function() isPlaying;
  const PlaybackTransport({
    required this.playPause,
    required this.next,
    required this.previous,
    required this.isPlaying,
  });
}

class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();
  static final DesktopTray instance = DesktopTray._();

  PlaybackTransport? _transport;
  bool _ready = false;

  static bool get supported => PlatformUtils.isWindows;

  /// Safe to call once at startup; any failure leaves the app without a tray.
  Future<void> init(PlaybackTransport transport) async {
    if (!supported || _ready) return;
    _transport = transport;
    try {
      await trayManager.setIcon('assets/tray/tray.ico');
      await trayManager.setToolTip('NaviVibe');
      trayManager.addListener(this);
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      _ready = true;
      await refreshMenu();
    } catch (e) {
      debugPrint('[Tray] unavailable: $e');
    }
  }

  /// Rebuilds the menu so the first item reads Play or Pause.
  Future<void> refreshMenu() async {
    if (!_ready) return;
    final playing = _transport?.isPlaying() ?? false;
    await trayManager.setContextMenu(
      Menu(items: [
        MenuItem(key: 'toggle', label: playing ? 'Pause' : 'Play'),
        MenuItem(key: 'next', label: 'Next'),
        MenuItem(key: 'previous', label: 'Previous'),
        MenuItem.separator(),
        MenuItem(key: 'show', label: 'Show NaviVibe'),
        MenuItem(key: 'quit', label: 'Quit'),
      ]),
    );
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() {
    refreshMenu().then((_) => trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        _transport?.playPause();
      case 'next':
        _transport?.next();
      case 'previous':
        _transport?.previous();
      case 'show':
        _show();
      case 'quit':
        _quit();
    }
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// Settings > Windows > Keep playing in the tray (default on).
  static bool get keepInTray {
    try {
      return HiveBoxes.prefs.get(HiveBoxes.kKeepPlayingInTray) != false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setKeepInTray(bool v) => HiveBoxes.prefs.put(HiveBoxes.kKeepPlayingInTray, v);

  /// Tooltip for the notification-area icon. Windows cuts it at 127 characters.
  @visibleForTesting
  static String tooltipFor({String? title, String? artist}) {
    if (title == null || title.isEmpty) return 'NaviVibe';
    final text = (artist == null || artist.isEmpty) ? title : '$title · $artist';
    return text.length <= 127 ? text : '${text.substring(0, 126)}…';
  }

  /// Shows the current song when the pointer rests on the tray icon.
  Future<void> setNowPlaying({String? title, String? artist}) async {
    if (!_ready) return;
    try {
      await trayManager.setToolTip(tooltipFor(title: title, artist: artist));
    } catch (e) {
      debugPrint('[Tray] tooltip failed: $e');
    }
  }

  @override
  void onWindowClose() async {
    // With the setting on, closing hides the window and music keeps playing;
    // Quit in the tray menu is the way out. Off: closing ends the app.
    if (keepInTray) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }
}
