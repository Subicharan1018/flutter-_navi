import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hive_ce/hive.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// window_manager_service.dart — Desktop window state persistence
//
// Persists window size and position across sessions using Hive.
// Must be attached as a WindowListener; call attach() early in main() after
// window_manager is initialized.
//
// Usage (in MyMusicPlayerApp or a root widget):
//   @override
//   void initState() {
//     super.initState();
//     WindowManagerService.instance.attach();
//   }
//
//   @override
//   void dispose() {
//     WindowManagerService.instance.detach();   // ← prevents listener leak
//     super.dispose();
//   }
// =============================================================================

class WindowManagerService with WindowListener {
  WindowManagerService._();
  static final WindowManagerService instance = WindowManagerService._();

  // ── Hive box key names ─────────────────────────────────────────────────────
  static const String _boxName = 'window_state';
  static const String _keyWidth  = 'w';
  static const String _keyHeight = 'h';
  static const String _keyX      = 'x';
  static const String _keyY      = 'y';

  bool _attached = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Registers this listener with window_manager and restores the last
  /// saved window position/size.  Safe to call multiple times (no-op).
  Future<void> attach() async {
    if (!PlatformUtils.supportsWindowManager) return;
    if (_attached) return;
    _attached = true;
    windowManager.addListener(this);
    await _restoreWindowState();
  }

  /// Removes the listener.  Must be called in dispose() to prevent leaks
  /// during hot restarts (harmless in production but confusing in debug).
  void detach() {
    if (!_attached) return;
    _attached = false;
    windowManager.removeListener(this);
  }

  // ── WindowListener overrides ───────────────────────────────────────────────

  @override
  void onWindowResized() => _saveWindowState();

  @override
  void onWindowMoved() => _saveWindowState();

  @override
  void onWindowClose() => _saveWindowState();

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _saveWindowState() async {
    try {
      final size     = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final box = await Hive.openBox<dynamic>(_boxName);
      await box.putAll({
        _keyWidth:  size.width,
        _keyHeight: size.height,
        _keyX:      position.dx,
        _keyY:      position.dy,
      });
    } catch (e) {
      // Non-fatal — next launch simply uses the default size.
      debugPrint('[WindowManager] Failed to save window state: $e');
    }
  }

  Future<void> _restoreWindowState() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      final w = box.get(_keyWidth)  as double?;
      final h = box.get(_keyHeight) as double?;
      final x = box.get(_keyX)      as double?;
      final y = box.get(_keyY)      as double?;

      if (w != null && h != null) {
        // Clamp to minimum size so a corrupted value never hides the window.
        final clampedSize = Size(
          w.clamp(PlatformUtils.kDesktopBreakpoint, 8000),
          h.clamp(PlatformUtils.kWideScreenBreakpoint, 6000),
        );
        await windowManager.setSize(clampedSize);
      }

      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
    } catch (e) {
      debugPrint('[WindowManager] Failed to restore window state: $e');
    }
  }
}

// =============================================================================
// WindowLifecycleObserver — mixin for the root app widget
//
// Add this mixin to AppScaffold or MyMusicPlayerApp and call super in
// initState / dispose to automatically attach/detach the listener.
// =============================================================================

mixin WindowLifecycleMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    if (PlatformUtils.supportsWindowManager) {
      WindowManagerService.instance.attach();
    }
  }

  @override
  void dispose() {
    if (PlatformUtils.supportsWindowManager) {
      WindowManagerService.instance.detach();
    }
    super.dispose();
  }
}
