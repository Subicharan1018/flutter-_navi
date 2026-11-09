import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/hive_boxes.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// global_hotkey.dart — the system-wide shortcut that brings NaviVibe forward.
//
// Default Ctrl+Alt+Space (Settings > Windows can change or turn it off). It
// works while another app has focus: it shows the window, takes focus and puts
// the caret in the search field. Registration goes through a [HotkeyDriver],
// so the logic is tested with a fake; [HotkeyManagerDriver] is the only code
// that touches hotkey_manager. Windows refuses a combination another app owns;
// that is reported as a false return, never thrown.
// =============================================================================

enum HotkeyModifierKey { control, alt, shift, meta }

/// A key plus modifiers, in a form that is stored, shown and registered.
@immutable
class HotkeyBinding {
  final LogicalKeyboardKey key;
  final Set<HotkeyModifierKey> modifiers;
  const HotkeyBinding(this.key, this.modifiers);

  static final defaultBinding = HotkeyBinding(
    LogicalKeyboardKey.space,
    const {HotkeyModifierKey.control, HotkeyModifierKey.alt},
  );

  /// A global shortcut needs a modifier, or typing that key anywhere would trigger it.
  bool get isValid => modifiers.isNotEmpty && !isModifierKey(key);

  /// Ctrl+Alt+Space.
  String get label {
    const order = [HotkeyModifierKey.control, HotkeyModifierKey.alt, HotkeyModifierKey.shift, HotkeyModifierKey.meta];
    const names = {
      HotkeyModifierKey.control: 'Ctrl',
      HotkeyModifierKey.alt: 'Alt',
      HotkeyModifierKey.shift: 'Shift',
      HotkeyModifierKey.meta: 'Win',
    };
    final k = key.keyLabel.isEmpty ? key.debugName ?? '?' : key.keyLabel;
    final shown = k == ' ' ? 'Space' : (k.length == 1 ? k.toUpperCase() : k);
    return [for (final m in order) if (modifiers.contains(m)) names[m]!, shown].join('+');
  }

  String encode() => jsonEncode({'key': key.keyId, 'mods': [for (final m in modifiers) m.name]});

  /// Null when [raw] is missing, damaged or not a usable shortcut.
  static HotkeyBinding? decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final key = LogicalKeyboardKey.findKeyByKeyId(m['key'] as int);
      if (key == null) return null;
      final mods = <HotkeyModifierKey>{
        for (final n in (m['mods'] as List).cast<String>())
          ...HotkeyModifierKey.values.where((v) => v.name == n),
      };
      final b = HotkeyBinding(key, mods);
      return b.isValid ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// The combination just pressed, or null while only modifiers are down.
  static HotkeyBinding? fromKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> pressed) {
    final key = event.logicalKey;
    if (isModifierKey(key)) return null;
    bool any(List<LogicalKeyboardKey> l) => l.any(pressed.contains);
    return HotkeyBinding(key, {
      if (any(const [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight])) HotkeyModifierKey.control,
      if (any(const [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight])) HotkeyModifierKey.alt,
      if (any(const [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight])) HotkeyModifierKey.shift,
      if (any(const [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight])) HotkeyModifierKey.meta,
    });
  }

  static bool isModifierKey(LogicalKeyboardKey k) => {
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.meta,
      }.contains(k);

  @override
  bool operator ==(Object other) => other is HotkeyBinding && other.key == key && setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(modifiers));
}

abstract class HotkeyDriver {
  /// Registers [binding]; throws if the system refuses it.
  Future<void> register(HotkeyBinding binding, VoidCallback onPressed);
  Future<void> unregisterAll();
}

class HotkeyManagerDriver implements HotkeyDriver {
  const HotkeyManagerDriver();

  @override
  Future<void> register(HotkeyBinding binding, VoidCallback onPressed) {
    final mods = <HotKeyModifier>[
      for (final m in binding.modifiers)
        switch (m) {
          HotkeyModifierKey.control => HotKeyModifier.control,
          HotkeyModifierKey.alt => HotKeyModifier.alt,
          HotkeyModifierKey.shift => HotKeyModifier.shift,
          HotkeyModifierKey.meta => HotKeyModifier.meta,
        },
    ];
    return hotKeyManager.register(
      HotKey(key: binding.key, modifiers: mods, scope: HotKeyScope.system),
      keyDownHandler: (_) => onPressed(),
    );
  }

  @override
  Future<void> unregisterAll() => hotKeyManager.unregisterAll();
}

class GlobalHotkey {
  GlobalHotkey({HotkeyDriver? driver}) : _driver = driver ?? const HotkeyManagerDriver();

  static final GlobalHotkey instance = GlobalHotkey();

  static bool get supported => PlatformUtils.isWindows;

  final HotkeyDriver _driver;
  VoidCallback? _onPressed;

  /// Settings > Windows > Global shortcut (default on).
  static bool get enabled {
    try {
      return HiveBoxes.prefs.get(HiveBoxes.kGlobalHotkeyEnabled) != false;
    } catch (_) {
      return true;
    }
  }

  static HotkeyBinding get binding {
    try {
      return HotkeyBinding.decode(HiveBoxes.prefs.get(HiveBoxes.kGlobalHotkey)) ?? HotkeyBinding.defaultBinding;
    } catch (_) {
      return HotkeyBinding.defaultBinding;
    }
  }

  /// Registers the saved shortcut. [onPressed] runs on every press.
  Future<bool> init(VoidCallback onPressed) {
    _onPressed = onPressed;
    return apply();
  }

  /// Re-registers from the saved settings. False: off, or the system refused it.
  Future<bool> apply() async {
    final onPressed = _onPressed;
    if (onPressed == null) return false;
    try {
      await _driver.unregisterAll();
      if (!enabled) return false;
      await _driver.register(binding, onPressed);
      return true;
    } catch (e) {
      debugPrint('[Hotkey] unavailable: $e');
      return false;
    }
  }

  Future<bool> setEnabled(bool v) async {
    await HiveBoxes.prefs.put(HiveBoxes.kGlobalHotkeyEnabled, v);
    return apply();
  }

  /// Saves and registers [b]. When the system refuses it the previous shortcut
  /// stays saved and registered, and this returns false.
  Future<bool> setBinding(HotkeyBinding b) async {
    if (!b.isValid) return false;
    final previous = HiveBoxes.prefs.get(HiveBoxes.kGlobalHotkey);
    await HiveBoxes.prefs.put(HiveBoxes.kGlobalHotkey, b.encode());
    final ok = await apply();
    if (!ok && enabled) {
      if (previous == null) {
        await HiveBoxes.prefs.delete(HiveBoxes.kGlobalHotkey);
      } else {
        await HiveBoxes.prefs.put(HiveBoxes.kGlobalHotkey, previous);
      }
      await apply();
    }
    return ok;
  }
}
