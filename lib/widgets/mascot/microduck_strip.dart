import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme.dart';
import '../../models/song.dart';
import '../../player/player_controls.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'microduck.dart';
import 'microduck_pose.dart';

/// Microduck walking along a line: [progress] (0..1) is where it stands.
/// Shows nothing when the mascot is switched off in Settings.
///
/// The hook for Replay's streak and month pages:
///
/// ```dart
/// MicroduckStrip(progress: daysListened / daysInMonth)
/// ```
///
/// * [progress] 0..1, clamped. Moves are glided over 500 ms.
/// * [playing] true trots, false stands (default true: a strip that has a
///   progress to show is on its way somewhere).
/// * [bpm] hops to that tempo when [danceOnBeat]; leave both off for pages.
/// * [height] of the strip; the duck is as tall as the strip. Default 28.
/// * [showTrack] draws the hairline it stands on; turn off when it sits
///   above a bar that already has one (Now Playing, mini player).
/// * [sleepsAtNight] naps between 00:00 and 05:00 local time.
/// * [color] line colour, default the theme's primary text.
class MicroduckStrip extends ConsumerWidget {
  final double progress;
  final bool playing;
  final int? bpm;
  final bool danceOnBeat;
  final double height;
  final bool showTrack;
  final bool sleepsAtNight;
  final Color? color;

  const MicroduckStrip({
    super.key,
    required this.progress,
    this.playing = true,
    this.bpm,
    this.danceOnBeat = false,
    this.height = 28,
    this.showTrack = true,
    this.sleepsAtNight = true,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider.select((s) => (s.microduckEnabled, s.microduckName)));
    if (!s.$1) return const SizedBox.shrink();

    final t = ThemeTokens.of(context);
    final pose = resolveMicroduckPose(
      playing: playing,
      now: DateTime.now(),
      reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      sleepsAtNight: sleepsAtNight,
      allowDance: danceOnBeat,
      bpm: bpm,
    );
    final lineColor = color ?? t.textPrimary;
    final f = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;

    return Semantics(
      label: '${s.$2} ${(f * 100).round()} percent along',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          final room = (c.maxWidth - height).clamp(0.0, double.infinity);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (showTrack)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * 0.04,
                  child: Container(height: 0.5, color: lineColor.withValues(alpha: 0.25)),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.linear,
                left: room * f,
                bottom: 0,
                child: Microduck(pose: pose, size: height, color: lineColor, bpm: bpm),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// A [MicroduckStrip] driven by the player: walks the song's progress while
/// it plays, stands when paused. Used by the mini player and Now Playing.
class PlayerMicroduckStrip extends ConsumerWidget {
  final AudioPlayer player;
  final Song song;
  final double height;
  final Color? color;

  /// Now Playing only: hop to the song's cached tempo and nap at night.
  final bool full;

  const PlayerMicroduckStrip({
    super.key,
    required this.player,
    required this.song,
    this.height = 28,
    this.color,
    this.full = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(settingsProvider.select((s) => s.microduckEnabled));
    if (!enabled) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final total = song.duration * 1000;
    return PlaybackPosition(
      player: player,
      songId: song.id,
      resolution: const Duration(milliseconds: 500),
      builder: (context, pos) => MicroduckStrip(
        progress: total > 0 ? pos.inMilliseconds / total : 0,
        playing: playing,
        bpm: full ? cachedBpm(song.id) : null,
        danceOnBeat: full,
        sleepsAtNight: full,
        showTrack: false,
        height: height,
        color: color,
      ),
    );
  }
}
