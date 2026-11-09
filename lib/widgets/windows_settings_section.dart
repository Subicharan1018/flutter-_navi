import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/desktop_tray.dart';
import '../services/global_hotkey.dart';
import '../services/windows_startup.dart';
import '../utils/platform_utils.dart';
import 'art/navi_icons.dart';
import 'ui/grouped_list.dart';

/// Settings > Windows: tray, start with Windows, the global shortcut. Hidden elsewhere.
class WindowsSettingsSection extends StatefulWidget {
  /// Replaceable in tests; the real ones talk to the registry and Windows.
  final WindowsStartup? startup;
  final GlobalHotkey? hotkey;
  const WindowsSettingsSection({super.key, this.startup, this.hotkey});

  @override
  State<WindowsSettingsSection> createState() => _WindowsSettingsSectionState();
}

class _WindowsSettingsSectionState extends State<WindowsSettingsSection> {
  late bool _inTray = DesktopTray.keepInTray;
  late final WindowsStartup _startup = widget.startup ?? WindowsStartup.instance;
  late final GlobalHotkey _hotkey = widget.hotkey ?? GlobalHotkey.instance;
  late bool _hotkeyOn = GlobalHotkey.enabled;
  late HotkeyBinding _binding = GlobalHotkey.binding;
  bool _atLogin = false;
  bool _recording = false;
  String? _note;
  final _recorder = FocusNode(debugLabel: 'hotkey-recorder');

  @override
  void initState() {
    super.initState();
    _startup.isEnabled().then((v) {
      if (mounted) setState(() => _atLogin = v);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _setAtLogin(bool v) async {
    setState(() => _atLogin = v);
    final ok = await _startup.setEnabled(v);
    if (!mounted || ok) return;
    setState(() {
      _atLogin = !v;
      _note = "Windows wouldn't let NaviVibe change its startup entry.";
    });
  }

  Future<void> _setHotkeyOn(bool v) async {
    setState(() {
      _hotkeyOn = v;
      _note = null;
    });
    final ok = await _hotkey.setEnabled(v);
    if (mounted && v && !ok) setState(() => _note = 'Another app already uses ${_binding.label}. Pick a different shortcut.');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      return KeyEventResult.handled;
    }
    final b = HotkeyBinding.fromKeyEvent(event, HardwareKeyboard.instance.logicalKeysPressed);
    if (b == null) return KeyEventResult.handled; // only modifiers so far
    if (!b.isValid) {
      setState(() => _note = 'Hold Ctrl, Alt, Shift or Win with the key.');
      return KeyEventResult.handled;
    }
    setState(() {
      _recording = false;
      _note = null;
    });
    _save(b);
    return KeyEventResult.handled;
  }

  Future<void> _save(HotkeyBinding b) async {
    final ok = await _hotkey.setBinding(b);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _binding = b;
        _hotkeyOn = true;
      } else {
        _note = '${b.label} is taken by another app. Pick a different shortcut.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isWindows) return const SizedBox.shrink();
    return Focus(
      focusNode: _recorder,
      onKeyEvent: _onKey,
      child: GroupedSection(
        header: 'Windows',
        footer: _note ??
            'Closing the window hides NaviVibe in the notification area. Quit from its icon to exit. '
                'The shortcut brings NaviVibe forward from any app and opens search.',
        children: [
          GroupedSwitchRow(
            title: 'Keep playing in the tray',
            icon: NaviGlyph.alert,
            value: _inTray,
            onChanged: (v) {
              setState(() => _inTray = v);
              DesktopTray.setKeepInTray(v);
            },
          ),
          GroupedSwitchRow(
            title: 'Start with Windows',
            subtitle: 'Opens minimized in the tray when you sign in',
            icon: NaviGlyph.play,
            value: _atLogin,
            onChanged: _setAtLogin,
          ),
          GroupedSwitchRow(
            title: 'Global shortcut',
            subtitle: 'Show NaviVibe and search from any app',
            icon: NaviGlyph.keyboard,
            value: _hotkeyOn,
            onChanged: _setHotkeyOn,
          ),
          GroupedRow(
            title: 'Shortcut',
            icon: NaviGlyph.keyboard,
            value: _recording ? 'Press keys, Esc to cancel' : _binding.label,
            onTap: () {
              setState(() {
                _recording = !_recording;
                _note = null;
              });
              if (_recording) _recorder.requestFocus();
            },
          ),
        ],
      ),
    );
  }
}
