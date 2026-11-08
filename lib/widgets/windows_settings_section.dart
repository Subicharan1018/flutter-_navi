import 'package:flutter/widgets.dart';

import '../services/desktop_tray.dart';
import '../utils/platform_utils.dart';
import 'art/navi_icons.dart';
import 'ui/grouped_list.dart';

/// Settings > Windows: what closing the window does. Hidden elsewhere.
class WindowsSettingsSection extends StatefulWidget {
  const WindowsSettingsSection({super.key});

  @override
  State<WindowsSettingsSection> createState() => _WindowsSettingsSectionState();
}

class _WindowsSettingsSectionState extends State<WindowsSettingsSection> {
  late bool _inTray = DesktopTray.keepInTray;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isWindows) return const SizedBox.shrink();
    return GroupedSection(
      header: 'Windows',
      footer: 'Closing the window hides NaviVibe in the notification area. Quit from its icon to exit.',
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
      ],
    );
  }
}
