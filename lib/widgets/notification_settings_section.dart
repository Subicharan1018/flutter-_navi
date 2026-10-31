import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/android_integration.dart';
import '../services/app_notifier.dart';
import '../utils/platform_utils.dart';
import 'art/navi_icons.dart';
import 'ui/grouped_list.dart';

/// Whether Android lets the app post notifications (always true elsewhere).
final notificationsAllowedProvider = FutureProvider.autoDispose<bool>(
  (ref) => AndroidIntegration.notificationsEnabled(),
);

/// Settings > Notifications: the app's own switch, plus on Android a way to
/// the system page when the permission was denied (Android stops showing the
/// prompt after two denials, so the app can't ask again itself).
class NotificationSettingsSection extends ConsumerStatefulWidget {
  const NotificationSettingsSection({super.key});

  @override
  ConsumerState<NotificationSettingsSection> createState() => _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState extends ConsumerState<NotificationSettingsSection> {
  late final AppLifecycleListener _lifecycle;
  late bool _on = AppNotifier.enabledPref;

  @override
  void initState() {
    super.initState();
    // Back from the system settings page: re-read the permission.
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(notificationsAllowedProvider));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isAndroid && !PlatformUtils.isWindows) return const SizedBox.shrink();
    final allowed = ref.watch(notificationsAllowedProvider).asData?.value ?? true;
    return GroupedSection(
      header: 'Notifications',
      footer: PlatformUtils.isAndroid && !allowed
          ? 'Notifications are off for NaviVibe in system settings. Downloads, updates and invitations won’t alert you.'
          : 'Downloads that finish, updates and invitations, while the app is in the background.',
      children: [
        GroupedSwitchRow(
          title: 'Notifications',
          icon: NaviGlyph.alert,
          value: _on,
          onChanged: (v) {
            setState(() => _on = v);
            AppNotifier.setEnabled(v);
          },
        ),
        if (PlatformUtils.isAndroid)
          GroupedRow(
            title: 'System settings',
            value: allowed ? 'Allowed' : 'Blocked',
            onTap: AndroidIntegration.openNotificationSettings,
          ),
      ],
    );
  }
}
