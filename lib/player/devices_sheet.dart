import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show InkWell, Material;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/player_provider.dart';
import '../providers/session_sync_provider.dart';
import '../services/session_sync_service.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/desktop_dialogs.dart';

/// The glyph for a kind of device.
NaviGlyph syncDeviceGlyph(SyncDeviceType t) => switch (t) {
      SyncDeviceType.phone || SyncDeviceType.tablet => NaviGlyph.phone,
      SyncDeviceType.desktop || SyncDeviceType.tv => NaviGlyph.desktop,
      SyncDeviceType.web => NaviGlyph.globe,
      SyncDeviceType.speaker => NaviGlyph.speaker,
      SyncDeviceType.unknown => NaviGlyph.headphones,
    };

/// One row of the sheet, ready to draw.
class DeviceRowData {
  final SyncDevice device;
  final bool isThis;
  final String title;
  final String caption;
  const DeviceRowData(this.device, this.isThis, this.title, this.caption);
}

/// Orders and names the devices: this one first, then the one playing, then
/// the rest by name. Two devices with the same name get their id's last four
/// characters so they can be told apart.
List<DeviceRowData> deviceRows(List<SyncDevice> devices, {required String? thisId, required bool thisPlayingHere}) {
  final byName = <String, int>{};
  for (final d in devices) {
    byName[d.name] = (byName[d.name] ?? 0) + 1;
  }
  final sorted = [...devices]..sort((a, b) {
      int rank(SyncDevice d) => d.id == thisId ? 0 : (d.active ? 1 : 2);
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return [
    for (final d in sorted)
      DeviceRowData(
        d,
        d.id == thisId,
        (byName[d.name] ?? 0) > 1 && d.id.length >= 4 ? '${d.name} · ${d.id.substring(d.id.length - 4)}' : d.name,
        _caption(d, isThis: d.id == thisId),
      ),
  ];
}

/// "This device · Playing here", "Host · seen 40 s ago" and the like.
String _caption(SyncDevice d, {required bool isThis}) {
  final parts = <String>[
    if (isThis) 'This device',
    if (d.active) (isThis ? 'Playing here' : 'Host · playing now') else (isThis ? 'Tap to play here' : 'Tap to move playback here'),
    if (!isThis && d.lastSeenS != null && d.lastSeenS! >= 20) 'seen ${d.lastSeenS!.round()} s ago',
  ];
  return parts.join(' · ');
}

Future<void> showDevicesSheet(BuildContext context) =>
    showPlatformSheet(context: context, title: 'Playing on', builder: (_) => const DevicesSheet());

class DevicesSheet extends ConsumerWidget {
  const DevicesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final conn = ref.watch(syncConnectionProvider).asData?.value ?? SyncConnection.connecting;
    final devices = ref.watch(syncDevicesProvider).asData?.value ?? const <SyncDevice>[];
    final service = ref.read(sessionSyncServiceProvider);
    final thisId = service.deviceId;
    final mode = ref.watch(playerProvider.select((s) => s.syncMode));
    final thisHere = mode == SyncMode.activeHere;

    // The server lists devices once the link is up; until then, show this one.
    final shown = devices.isEmpty
        ? [SyncDevice(id: thisId ?? 'this', name: service.deviceName ?? 'This device', active: thisHere)]
        : devices;
    final rows = deviceRows(shown, thisId: thisId ?? (devices.isEmpty ? 'this' : null), thisPlayingHere: thisHere);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (conn != SyncConnection.online)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
              child: Row(children: [
                if (conn == SyncConnection.connecting)
                  const CupertinoActivityIndicator(radius: 8)
                else
                  NaviIcon(NaviGlyph.wifiOff, size: 18, color: t.textMuted),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    conn == SyncConnection.connecting
                        ? 'Connecting to your devices…'
                        : 'Can’t reach your other devices. Playback here keeps working.',
                    style: t.footnote,
                  ),
                ),
                if (conn == SyncConnection.offline)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    minimumSize: const Size(44, 44),
                    onPressed: () => service.connect(),
                    child: Text('Try again', style: t.callout.copyWith(color: t.accent)),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.group),
              child: ColoredBox(
                color: t.bgElevated,
                child: Column(children: [
                  for (final (i, r) in rows.indexed) ...[
                    _DeviceRow(row: r, enabled: conn == SyncConnection.online || r.isThis),
                    if (i < rows.length - 1) Container(height: 0.5, color: t.outline),
                  ],
                ]),
              ),
            ),
          ),
          if (rows.length < 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
              child: Text(
                'Open NaviVibe on another device and sign in with the same account. It shows up here, and you can send music to it or control it from this one.',
                style: t.footnote,
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  final DeviceRowData row;
  final bool enabled;
  const _DeviceRow({required this.row, required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final active = row.device.active;
    final color = enabled ? t.textPrimary : t.textMuted;
    return Semantics(
      button: !active,
      selected: active,
      label: '${row.title}. ${row.caption}',
      excludeSemantics: true,
      child: Material(
        color: const Color(0x00000000),
        child: InkWell(
          onTap: !enabled || active
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                  ref.read(playerProvider.notifier).transferTo(row.device.id);
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Row(children: [
                NaviIcon(syncDeviceGlyph(row.device.type), size: 26, color: active ? t.accent : color, filled: active),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(row.title, style: t.body.copyWith(color: active ? t.accent : color, fontWeight: active ? FontWeight.w600 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(row.caption, style: t.footnote),
                  ]),
                ),
                if (active) ...[
                  Text('Host', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
                  const SizedBox(width: Space.sm),
                  NaviIcon(NaviGlyph.speaker, size: 20, color: t.accent),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
