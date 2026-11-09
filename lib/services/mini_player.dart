import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/platform_utils.dart';
import 'window_manager_service.dart';

// =============================================================================
// mini_player.dart — the always-on-top mini player mode (Windows).
//
// The same window shrinks to [size], floats above other windows and shows
// MiniPlayerView instead of the app. Leaving puts back the size, position and
// maximized state it had. The window calls go through a [MiniWindow], so the
// logic is tested with a fake; [WindowManagerMiniWindow] is the only code that
// touches window_manager.
// =============================================================================

abstract class MiniWindow {
  Future<Rect> bounds();
  Future<bool> isMaximized();
  Future<void> setMaximized(bool maximized);
  Future<void> setBounds(Rect bounds);
  Future<void> setMinimumSize(Size size);
  Future<void> setResizable(bool resizable);
  Future<void> setAlwaysOnTop(bool onTop);
  Future<void> show();
}

class WindowManagerMiniWindow implements MiniWindow {
  const WindowManagerMiniWindow();

  @override
  Future<Rect> bounds() async {
    final p = await windowManager.getPosition();
    final s = await windowManager.getSize();
    return p & s;
  }

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> setMaximized(bool maximized) => maximized ? windowManager.maximize() : windowManager.unmaximize();

  @override
  Future<void> setBounds(Rect b) async {
    await windowManager.setSize(b.size);
    await windowManager.setPosition(b.topLeft);
  }

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setResizable(bool resizable) => windowManager.setResizable(resizable);

  @override
  Future<void> setAlwaysOnTop(bool onTop) => windowManager.setAlwaysOnTop(onTop);

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }
}

class MiniPlayer {
  MiniPlayer({MiniWindow? window, Size? fullMinimum})
      : _window = window ?? const WindowManagerMiniWindow(),
        _fullMinimum = fullMinimum ?? WindowManagerService.minimumSize;

  static final MiniPlayer instance = MiniPlayer();

  /// The mini window: a cover, the song, transport and a seek bar.
  static const Size size = Size(380, 168);

  static bool get supported => PlatformUtils.isDesktop;

  final MiniWindow _window;
  final Size _fullMinimum;

  /// True while the window is in mini mode. The app shows MiniPlayerView then.
  final ValueNotifier<bool> active = ValueNotifier(false);

  Rect? _savedBounds;
  bool _savedMaximized = false;
  bool _busy = false;

  /// Where the full window will return to, while in mini mode.
  @visibleForTesting
  Rect? get savedBounds => _savedBounds;

  Future<void> toggle() => active.value ? exit() : enter();

  Future<void> enter() async {
    if (_busy || active.value) return;
    _busy = true;
    try {
      await _window.show();
      _savedMaximized = await _window.isMaximized();
      if (_savedMaximized) await _window.setMaximized(false);
      _savedBounds = await _window.bounds();
      await _window.setMinimumSize(size);
      await _window.setResizable(false);
      final b = _savedBounds!;
      // Opens where the full window's top-right corner was, so it stays on that screen.
      await _window.setBounds(Rect.fromLTWH(b.right - size.width, b.top, size.width, size.height));
      await _window.setAlwaysOnTop(true);
      WindowManagerService.suspendSaving = true;
      active.value = true;
    } catch (e) {
      debugPrint('[Mini] enter failed: $e');
      await _restore();
    } finally {
      _busy = false;
    }
  }

  Future<void> exit() async {
    if (_busy || !active.value) return;
    _busy = true;
    try {
      active.value = false;
      await _restore();
    } finally {
      _busy = false;
    }
  }

  /// Puts the window back as it was. Every step is attempted, none may throw.
  Future<void> _restore() async {
    Future<void> step(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('[Mini] restore step failed: $e');
      }
    }

    await step(() => _window.setAlwaysOnTop(false));
    await step(() => _window.setResizable(true));
    await step(() => _window.setMinimumSize(_fullMinimum));
    final b = _savedBounds;
    if (b != null) await step(() => _window.setBounds(b));
    if (_savedMaximized) await step(() => _window.setMaximized(true));
    WindowManagerService.suspendSaving = false;
    _savedBounds = null;
    _savedMaximized = false;
  }
}
