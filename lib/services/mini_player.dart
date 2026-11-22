import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';
import 'window_manager_service.dart';

// =============================================================================
// mini_player.dart — the always-on-top mini player mode (Windows).
//
// The same window shrinks to a small size, floats above other windows (unless
// the user un-pins it) and shows MiniPlayerView instead of the app. There are
// two shapes: a [MiniMode.bar] strip and a [MiniMode.cover] square. The shape,
// the pin and where the user left the mini window are remembered.
//
// Leaving puts back the size, position and maximized state the full window
// had. The window calls go through a [MiniWindow], and the remembered values
// through a [MiniStore], so the logic is tested with fakes;
// [WindowManagerMiniWindow] is the only code that touches window_manager.
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
  Future<void> setMaximized(bool maximized) =>
      maximized ? windowManager.maximize() : windowManager.unmaximize();

  @override
  Future<void> setBounds(Rect b) async {
    await windowManager.setSize(b.size);
    await windowManager.setPosition(b.topLeft);
  }

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setResizable(bool resizable) =>
      windowManager.setResizable(resizable);

  @override
  Future<void> setAlwaysOnTop(bool onTop) =>
      windowManager.setAlwaysOnTop(onTop);

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }
}

/// The two shapes of the mini window.
enum MiniMode { bar, cover }

/// What the mini window remembers between launches.
class MiniPrefs {
  final MiniMode mode;
  final bool pinned;

  /// Top-left corner of the mini window where the user last left it.
  final Offset? origin;
  const MiniPrefs({this.mode = MiniMode.bar, this.pinned = true, this.origin});

  MiniPrefs copyWith({MiniMode? mode, bool? pinned, Offset? origin}) =>
      MiniPrefs(
        mode: mode ?? this.mode,
        pinned: pinned ?? this.pinned,
        origin: origin ?? this.origin,
      );
}

abstract class MiniStore {
  MiniPrefs load();
  void save(MiniPrefs prefs);
}

/// Keeps [MiniPrefs] in the prefs box. Never throws: a box that is not open
/// (tests, a failed start) reads as the defaults and writes nothing.
class HiveMiniStore implements MiniStore {
  const HiveMiniStore();
  static const _key = 'mini_player_v1';

  @override
  MiniPrefs load() {
    try {
      final raw = HiveBoxes.prefs.get(_key);
      if (raw is! Map) return const MiniPrefs();
      final mode = raw['mode'] == 'cover' ? MiniMode.cover : MiniMode.bar;
      final x = raw['x'], y = raw['y'];
      return MiniPrefs(
        mode: mode,
        pinned: raw['pinned'] != false,
        origin: x is num && y is num
            ? Offset(x.toDouble(), y.toDouble())
            : null,
      );
    } catch (_) {
      return const MiniPrefs();
    }
  }

  @override
  void save(MiniPrefs p) {
    try {
      HiveBoxes.prefs.put(_key, {
        'mode': p.mode.name,
        'pinned': p.pinned,
        if (p.origin != null) 'x': p.origin!.dx,
        if (p.origin != null) 'y': p.origin!.dy,
      });
    } catch (e) {
      debugPrint('[Mini] could not save: $e');
    }
  }
}

class MiniPlayer {
  MiniPlayer({MiniWindow? window, Size? fullMinimum, MiniStore? store})
    : _window = window ?? const WindowManagerMiniWindow(),
      _fullMinimum = fullMinimum ?? WindowManagerService.minimumSize,
      _store = store ?? const HiveMiniStore() {
    final p = _store.load();
    mode = ValueNotifier(p.mode);
    pinned = ValueNotifier(p.pinned);
    _origin = p.origin;
  }

  static final MiniPlayer instance = MiniPlayer();

  /// The strip: art on the left, song, transport and the scrubber on its edge.
  static const Size barSize = Size(360, 96);

  /// The square: the cover full-bleed with the song and transport on it.
  static const Size coverSize = Size(360, 360);

  static Size sizeFor(MiniMode m) => m == MiniMode.bar ? barSize : coverSize;

  /// A separate small OS window: native desktop only, never in a browser.
  static bool get supported => PlatformUtils.isNativeDesktop;

  final MiniWindow _window;
  final Size _fullMinimum;
  final MiniStore _store;

  /// True while the window is in mini mode. The app shows MiniPlayerView then.
  final ValueNotifier<bool> active = ValueNotifier(false);

  /// The shape the mini window has (or will have next time).
  late final ValueNotifier<MiniMode> mode;

  /// Whether the mini window floats above other windows.
  late final ValueNotifier<bool> pinned;

  Offset? _origin;
  Rect? _savedBounds;
  bool _savedMaximized = false;
  bool _busy = false;

  Size get size => sizeFor(mode.value);

  /// Where the mini window was last left, if anywhere.
  @visibleForTesting
  Offset? get origin => _origin;

  /// A remembered corner is only trusted when it is near the desktop: a
  /// monitor that was unplugged since would otherwise hide the window.
  static bool _sane(Offset o) =>
      o.dx > -200 && o.dx < 8000 && o.dy > -40 && o.dy < 4500;

  Future<void> toggle() => active.value ? exit() : enter();

  Future<void> enter() async {
    if (_busy || active.value) return;
    _busy = true;
    try {
      await _window.show();
      _savedMaximized = await _window.isMaximized();
      if (_savedMaximized) await _window.setMaximized(false);
      _savedBounds = await _window.bounds();
      // The smallest shape is the floor, so growing to the square needs no
      // minimum change and shrinking back is never refused.
      await _window.setMinimumSize(barSize);
      await _window.setResizable(false);
      final b = _savedBounds!;
      final s = size;
      final o = _origin;
      // Opens where it was left; the first time, where the full window's
      // top-right corner was, so it stays on that screen.
      final at = o != null && _sane(o) ? o : Offset(b.right - s.width, b.top);
      await _window.setBounds(at & s);
      await _window.setAlwaysOnTop(pinned.value);
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
      await rememberPosition();
      active.value = false;
      await _restore();
    } finally {
      _busy = false;
    }
  }

  /// Switches between the strip and the square, keeping the top-left corner.
  Future<void> setMode(MiniMode m) async {
    if (m == mode.value) return;
    mode.value = m;
    _save();
    if (!active.value) return;
    try {
      final b = await _window.bounds();
      await _window.setBounds(b.topLeft & sizeFor(m));
      _origin = b.topLeft;
    } catch (e) {
      debugPrint('[Mini] resize failed: $e');
    }
  }

  Future<void> toggleMode() =>
      setMode(mode.value == MiniMode.bar ? MiniMode.cover : MiniMode.bar);

  /// Pins the mini window above other windows, or lets it sit among them.
  Future<void> setPinned(bool value) async {
    if (value == pinned.value) return;
    pinned.value = value;
    _save();
    if (!active.value) return;
    try {
      await _window.setAlwaysOnTop(value);
    } catch (e) {
      debugPrint('[Mini] pin failed: $e');
    }
  }

  Future<void> togglePinned() => setPinned(!pinned.value);

  /// Remembers where the user left the window; called when a drag ends.
  Future<void> rememberPosition() async {
    if (!active.value && !_busy) return;
    try {
      final b = await _window.bounds();
      _origin = b.topLeft;
      _save();
    } catch (_) {}
  }

  void _save() => _store.save(
    MiniPrefs(mode: mode.value, pinned: pinned.value, origin: _origin),
  );

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
