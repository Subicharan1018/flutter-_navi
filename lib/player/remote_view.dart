import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/player_provider.dart';
import '../providers/session_sync_provider.dart';
import '../providers/settings_provider.dart';
import '../services/session_sync_service.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/cover_art.dart';
import '../widgets/ui/action_sheet.dart' show showToast;
import 'devices_sheet.dart';
import 'player_controls.dart';

/// Where the playhead of [s] is now, projected from when the server stamped it.
///
/// The server stamped the position with its own clock, so "now" is the server's now:
/// [offsetMs] is the measured difference between its clock and this device's, which
/// keeps a phone whose clock is minutes off from showing a playhead that races or stalls.
Duration remotePosition(PlaybackState s, DateTime now, {int offsetMs = 0}) {
  var ms = s.positionMs;
  final stamp = s.positionAtServerMs ?? s.updatedAt?.millisecondsSinceEpoch;
  if (s.isPlaying && stamp != null) {
    final elapsed = now.millisecondsSinceEpoch + offsetMs - stamp;
    if (elapsed > 0) ms += elapsed;
  }
  final total = (s.durationS * 1000).round();
  if (total > 0 && ms > total) ms = total;
  return Duration(milliseconds: ms < 0 ? 0 : ms);
}

/// Now Playing while another of your devices holds playback: this phone is the
/// remote. It shows that device's song and playhead and its buttons drive the
/// other device; nothing plays here.
class RemoteControlView extends ConsumerStatefulWidget {
  const RemoteControlView({super.key});

  @override
  ConsumerState<RemoteControlView> createState() => _RemoteControlViewState();
}

class _RemoteControlViewState extends ConsumerState<RemoteControlView> {
  Timer? _tick;
  StreamSubscription<CommandResult>? _results;
  double? _dragging; // 0..1 while the scrubber is held
  double _volume = 0.8; // the other device's volume isn't reported; this is the remote's own setting

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _dragging == null) setState(() {});
    });
    _results = ref.read(sessionSyncServiceProvider).resultStream.listen((r) {
      if (!r.ok && mounted) showToast(context, r.message);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _results?.cancel();
    super.dispose();
  }

  PlayerNotifier get _player => ref.read(playerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncPlaybackProvider).asData?.value ?? const PlaybackState.initial();
    final conn = ref.watch(syncConnectionProvider).asData?.value ?? SyncConnection.online;
    final svc = ref.read(subsonicServiceProvider);
    final width = MediaQuery.sizeOf(context).width;
    final cover = (width - 56).clamp(200.0, 320.0);
    final total = (s.durationS * 1000).round();
    final pos = remotePosition(s, DateTime.now(), offsetMs: ref.read(sessionSyncServiceProvider).clock.offsetMs);
    final frac = _dragging ?? (total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0);
    final shown = Duration(milliseconds: (frac * total).round());
    const ink = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.72);

    Widget button(NaviGlyph g, String label, VoidCallback onTap, {double size = 40, double box = 72}) => GlyphButton(
          size: box,
          semanticLabel: label,
          onTap: onTap,
          child: NaviIcon(g, size: size, color: ink),
        );

    return Column(
      children: [
        const SizedBox(height: 8),
        // Grabber doubles as "close".
        GestureDetector(
          onTap: () => Navigator.maybePop(context),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 28,
            width: 120,
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ),
        RemoteDeviceBanner(name: s.activeDeviceName, offline: conn == SyncConnection.offline),
        Expanded(
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.hero),
              child: CoverArt(
                url: s.coverArtId == null || s.coverArtId!.isEmpty ? null : svc.getCoverArtUrl(s.coverArtId),
                size: cover,
                radius: 0,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.trackTitle ?? 'Nothing playing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: naviText(22, FontWeight.w700, ink),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(s.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: naviText(17, FontWeight.w400, dim)),
            ),
            const SizedBox(height: 14),
            ElasticTrack(
              value: frac,
              activeColor: ink,
              inactiveColor: Colors.white.withValues(alpha: 0.28),
              semanticLabel: 'Playback position on ${s.activeDeviceName ?? 'the other device'}',
              onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
              onChangeEnd: total > 0
                  ? (v) {
                      setState(() => _dragging = null);
                      _player.remoteControl('seek', positionMs: (v * total).round());
                    }
                  : null,
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatClock(shown), style: naviText(12, FontWeight.w500, dim)),
              Text(total > 0 ? '-${formatClock(Duration(milliseconds: total) - shown)}' : '', style: naviText(12, FontWeight.w500, dim)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              button(NaviGlyph.rewind, 'Previous', () => _player.remoteControl('prev'), size: 42),
              button(s.isPlaying ? NaviGlyph.pause : NaviGlyph.play, s.isPlaying ? 'Pause' : 'Play',
                  () => _player.remoteControl(s.isPlaying ? 'pause' : 'play'), size: 52, box: 84),
              button(NaviGlyph.fastForward, 'Next', () => _player.remoteControl('next'), size: 42),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              NaviIcon(NaviGlyph.speakerLow, size: 18, color: dim),
              const SizedBox(width: 10),
              Expanded(
                child: ElasticTrack(
                  value: _volume,
                  activeColor: ink,
                  inactiveColor: Colors.white.withValues(alpha: 0.28),
                  semanticLabel: 'Volume on ${s.activeDeviceName ?? 'the other device'}',
                  onChanged: (v) => setState(() => _volume = v),
                  onChangeEnd: (v) => _player.remoteControl('volume', volume: v),
                ),
              ),
              const SizedBox(width: 10),
              NaviIcon(NaviGlyph.speaker, size: 18, color: dim),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _Pill(label: 'Play here', glyph: NaviGlyph.play, onTap: () => _player.claimActiveDevice()),
              _Pill(label: 'Devices', glyph: NaviGlyph.headphones, onTap: () => showDevicesSheet(context)),
            ]),
            const SizedBox(height: 14),
          ]),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final NaviGlyph glyph;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.capsule)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              NaviIcon(glyph, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: naviText(14, FontWeight.w600, Colors.white)),
            ]),
          ),
        ),
      );
}

/// Shown above the cover while another device holds playback: whose it is, and
/// when the link to it is down, that the controls can't reach it.
class RemoteDeviceBanner extends StatelessWidget {
  final String? name;
  final bool offline;
  const RemoteDeviceBanner({super.key, required this.name, required this.offline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        NaviIcon(offline ? NaviGlyph.wifiOff : NaviGlyph.speaker, size: 18, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            offline ? 'Reconnecting to ${name ?? 'your devices'}…' : 'Playing on ${name ?? 'another device'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: naviText(13.5, FontWeight.w600, Colors.white),
          ),
        ),
      ]),
    );
  }
}
