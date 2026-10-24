import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import '../../player/player_controls.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'microduck.dart';
import 'microduck_pose.dart';

/// The Microduck robot standing at [progress] (0..1) along a line. Shows
/// nothing when the mascot is switched off in Settings.
///
/// The hook for Replay's streak and month pages:
///
/// ```dart
/// MicroduckStrip(progress: daysListened / daysInMonth, height: 64)
/// ```
///
/// * [progress] 0..1, clamped. Moves are glided over 500 ms.
/// * [playing] true walks (or dances with [danceOnBeat]), false stands
///   (default true: a strip that has a progress to show is on its way).
/// * [bpm] tempo to dance to; null uses 100 bpm.
/// * [height] of the strip; the robot is as tall as the strip, so 32+ reads
///   as a robot (mini bar ~34, Now Playing ~72, pages ~64). Default 64.
/// * [showTrack] draws the hairline it stands on; off when it stands above a
///   bar that already has one.
/// * [sleepsAtNight] naps between 00:00 and 05:00 local time.
/// * [interactive] taps hop it and a finger makes it look.
/// * [trackColor] colour of the hairline, default the theme's text.
class MicroduckStrip extends ConsumerWidget {
  final double progress;
  final bool playing;
  final int? bpm;
  final bool danceOnBeat;
  final double height;
  final bool showTrack;
  final bool sleepsAtNight;
  final bool interactive;
  final Color? trackColor;

  const MicroduckStrip({
    super.key,
    required this.progress,
    this.playing = true,
    this.bpm,
    this.danceOnBeat = false,
    this.height = 64,
    this.showTrack = true,
    this.sleepsAtNight = true,
    this.interactive = true,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider.select((s) => (s.microduckEnabled, s.microduckName, s.microduckSkin)));
    if (!s.$1) return const SizedBox.shrink();

    final pose = resolveMicroduckPose(
      playing: playing,
      now: DateTime.now(),
      reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      sleepsAtNight: sleepsAtNight,
      allowDance: danceOnBeat,
    );
    final f = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final line = trackColor ?? Colors.white;

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
                  child: Container(height: 0.5, color: line.withValues(alpha: 0.25)),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.linear,
                left: room * f,
                bottom: 0,
                child: Microduck(
                  pose: pose,
                  size: height,
                  skin: s.$3,
                  bpm: bpm,
                  interactive: interactive,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// A [MicroduckStrip] driven by the player: follows the song's progress while
/// it plays, stands when paused. Used by the mini player and Now Playing.
class PlayerMicroduckStrip extends ConsumerWidget {
  final AudioPlayer player;
  final Song song;
  final double height;

  /// Now Playing: dance to the song's cached tempo, nap at night, react to
  /// taps. The mini player passes false and just walks.
  final bool full;

  const PlayerMicroduckStrip({
    super.key,
    required this.player,
    required this.song,
    this.height = 88,
    this.full = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(settingsProvider.select((s) => s.microduckEnabled));
    if (!enabled) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final total = song.duration * 1000;
    final bpm = full ? cachedBpm(song.id) : null;
    return PlaybackPosition(
      player: player,
      songId: song.id,
      resolution: const Duration(milliseconds: 500),
      builder: (context, pos) => MicroduckStrip(
        progress: total > 0 ? pos.inMilliseconds / total : 0,
        playing: playing,
        bpm: bpm,
        danceOnBeat: full,
        sleepsAtNight: full,
        interactive: full,
        showTrack: false,
        height: height,
      ),
    );
  }
}
