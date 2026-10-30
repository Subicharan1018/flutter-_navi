import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../widgets/shell/dock_glass.dart';
import '../providers/player_provider.dart';
import '../providers/session_sync_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart' show openNowPlaying;
import '../services/session_sync_service.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import 'devices_sheet.dart';
import 'player_controls.dart' show GlyphButton;

/// Who is playing, at a glance: "This device" on the host, "Playing on NAME"
/// on every other device. Tap for the full list. It stays out of the way when
/// this is the only device signed in.
class PlayingOnChip extends ConsumerWidget {
  /// Space under the chip, taken only while the chip shows.
  final double gap;
  const PlayingOnChip({super.key, this.gap = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerProvider.select((s) => s.syncMode));
    final host = ref.watch(playerProvider.select((s) => s.remoteActiveDeviceName));
    final others = ref.watch(syncDevicesProvider.select((d) => d.asData?.value.length ?? 0));
    final passive = mode == SyncMode.passive;
    final here = mode == SyncMode.activeHere;
    if (!passive && !(here && others >= 2)) return const SizedBox.shrink();

    final t = ThemeTokens.of(context);
    final label = passive ? 'Playing on ${host ?? 'another device'}' : 'This device is the host';
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Semantics(
      button: true,
      label: '$label. Show devices.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          showDevicesSheet(context);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(Radii.capsule),
            border: Border.all(color: DockGlass.of(context) ? dockCapsuleEdge(context, t.bgElevated) : t.outline, width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            NaviIcon(passive ? NaviGlyph.speaker : NaviGlyph.phone, size: 16, color: t.textPrimary),
            const SizedBox(width: Space.sm),
            Flexible(child: Text(label, style: t.footnote.copyWith(color: t.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
      ),
    );
  }
}

/// The mini player slot: the normal one while this device plays, the other
/// device's song with remote buttons while it doesn't, and the chip above it
/// when several devices are signed in.
class AdaptiveMiniPlayer extends ConsumerWidget {
  const AdaptiveMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passive = ref.watch(playerProvider.select((s) => s.syncMode == SyncMode.passive));
    if (passive) return const RemoteMiniPlayer();
    final chip = ref.watch(playerProvider.select((s) => s.syncMode == SyncMode.activeHere)) &&
        ref.watch(syncDevicesProvider.select((d) => (d.asData?.value.length ?? 0) >= 2));
    if (!chip) return const MiniPlayer();
    return const Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: EdgeInsets.only(bottom: Space.xs), child: PlayingOnChip()),
      MiniPlayer(),
    ]);
  }
}

/// Mini player for a song that is playing on another of your devices.
class RemoteMiniPlayer extends ConsumerWidget {
  const RemoteMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(syncPlaybackProvider).asData?.value ?? const PlaybackState.initial();
    final svc = ref.read(subsonicServiceProvider);
    final player = ref.read(playerProvider.notifier);
    final host = s.activeDeviceName ?? 'another device';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: Semantics(
        label: '${s.trackTitle ?? 'Nothing playing'}, playing on $host. Open controls.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openNowPlaying(context),
          child: Container(
            height: MiniPlayer.height,
            padding: const EdgeInsets.only(left: Space.sm, right: Space.xs),
            decoration: BoxDecoration(
              color: dockCapsuleFill(context, t.bgElevated),
              borderRadius: BorderRadius.circular(Radii.capsule),
              border: Border.all(color: DockGlass.of(context) ? dockCapsuleEdge(context, t.bgElevated) : t.outline, width: 0.5),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.thumb),
                child: CoverArt(
                  url: s.coverArtId == null || s.coverArtId!.isEmpty ? null : svc.getCoverArtUrl(s.coverArtId),
                  size: 42,
                  radius: 0,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.trackTitle ?? 'Nothing playing', style: t.callout.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(children: [
                    NaviIcon(NaviGlyph.speaker, size: 13, color: t.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(child: Text('Playing on $host', style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              ),
              GlyphButton(
                size: 44,
                semanticLabel: s.isPlaying ? 'Pause on $host' : 'Play on $host',
                onTap: () => player.remoteControl(s.isPlaying ? 'pause' : 'play'),
                child: NaviIcon(s.isPlaying ? NaviGlyph.pause : NaviGlyph.play, color: t.textPrimary, size: 24),
              ),
              GlyphButton(
                size: 44,
                semanticLabel: 'Next on $host',
                onTap: () => player.remoteControl('next'),
                child: NaviIcon(NaviGlyph.next, color: t.textPrimary, size: 24),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
