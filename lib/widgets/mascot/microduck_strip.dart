import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/song.dart';
import '../../player/player_controls.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'microduck.dart';
import 'microduck_chat.dart';
import 'microduck_pose.dart';
import 'microduck_talk.dart';

/// The Microduck robot standing at [progress] (0..1) along a line. Shows
/// nothing when the mascot is switched off in Settings.
///
/// The hook for Replay's streak and month pages:
///
/// ```dart
/// MicroduckStrip(progress: daysListened / daysInMonth, height: 64)
/// ```
///
/// * [progress] 0..1, clamped. Small moves glide over 500 ms; a jump of more
///   than 3% (a seek) makes it run there.
/// * [playing] true walks (or dances with [danceOnBeat]), false stands, or
///   sits with [sitWhenPaused] (default true: a strip that has a progress to
///   show is on its way).
/// * [bpm] tempo to dance to; null uses 100 bpm.
/// * [height] of the strip; the robot is as tall as the strip, so 32+ reads
///   as a robot (mini bar ~36, Now Playing ~88, pages ~64). Default 64.
/// * [showTrack] draws the hairline it stands on; off when it stands above a
///   bar that already has one.
/// * [sleepsAtNight] naps between 00:00 and 05:00 local time.
/// * [interactive] taps hop it, a finger makes it look, a long press bows.
/// * [enter] walks in from the left edge when first shown.
/// * [startleToken] changing it makes the robot jump (a skipped song);
///   [love] shows a heart on its screen (a liked song).
/// * [trackColor] colour of the hairline, default white.
class MicroduckStrip extends ConsumerStatefulWidget {
  final double progress;
  final bool playing;
  final int? bpm;
  final bool danceOnBeat;
  final double height;
  final bool showTrack;
  final bool sleepsAtNight;
  final bool interactive;
  final bool enter;

  /// See [Microduck.hitInsetBottom].
  final double hitInsetBottom;
  final bool sitWhenPaused;
  final Object? startleToken;
  final bool love;

  /// See [Microduck.positionSource], [Microduck.beatOffset] and
  /// [Microduck.onTap].
  final Duration Function()? positionSource;
  final double beatOffset;
  final VoidCallback? onTap;
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
    this.enter = false,
    this.hitInsetBottom = 0,
    this.sitWhenPaused = false,
    this.startleToken,
    this.love = false,
    this.positionSource,
    this.beatOffset = 0,
    this.onTap,
    this.trackColor,
  });

  @override
  ConsumerState<MicroduckStrip> createState() => _MicroduckStripState();
}

class _MicroduckStripState extends ConsumerState<MicroduckStrip> {
  static const _walkIn = Duration(milliseconds: 1300);
  static const _runLeg = Duration(milliseconds: 750);

  bool _entered = false;
  bool _walkingIn = false;
  bool _running = false;
  bool _runRight = true;
  double _last = 0;
  Timer? _walkTimer, _runTimer;

  @override
  void initState() {
    super.initState();
    _last = _clamp(widget.progress);
    if (widget.enter) {
      _walkingIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _entered = true);
      });
      _walkTimer = Timer(_walkIn + const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _walkingIn = false);
      });
    } else {
      _entered = true;
    }
  }

  static double _clamp(double p) => p.isFinite ? p.clamp(0.0, 1.0) : 0.0;

  @override
  void didUpdateWidget(MicroduckStrip old) {
    super.didUpdateWidget(old);
    final f = _clamp(widget.progress);
    // A new song restarts the line; that is not a seek to run to.
    if (!_walkingIn && widget.startleToken == old.startleToken && (f - _last).abs() > 0.03) {
      _running = true;
      _runRight = f > _last;
      _runTimer?.cancel();
      _runTimer = Timer(_runLeg, () {
        if (mounted) setState(() => _running = false);
      });
    }
    _last = f;
  }

  @override
  void dispose() {
    _walkTimer?.cancel();
    _runTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider.select((s) => (s.microduckEnabled, s.microduckName, s.microduckSkin)));
    if (!s.$1) return const SizedBox.shrink();

    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final height = widget.height;
    var pose = resolveMicroduckPose(
      playing: widget.playing,
      now: DateTime.now(),
      reducedMotion: reduced,
      sleepsAtNight: widget.sleepsAtNight,
      allowDance: widget.danceOnBeat,
      sitWhenPaused: widget.sitWhenPaused,
    );
    var right = true;
    if (!reduced && pose != MicroduckPose.sleep) {
      if (_walkingIn) {
        pose = MicroduckPose.walk;
      } else if (_running) {
        pose = MicroduckPose.run;
        right = _runRight;
      }
    }
    final f = _clamp(widget.progress);
    final line = widget.trackColor ?? Colors.white;

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
              if (widget.showTrack)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * 0.04,
                  child: Container(height: 0.5, color: line.withValues(alpha: 0.25)),
                ),
              AnimatedPositioned(
                duration: _walkingIn ? _walkIn : (_running ? _runLeg : const Duration(milliseconds: 500)),
                curve: _walkingIn || _running ? Curves.easeInOut : Curves.linear,
                left: _entered ? room * f : -height * 1.1,
                bottom: 0,
                child: Microduck(
                  pose: pose,
                  size: height,
                  skin: s.$3,
                  bpm: widget.bpm,
                  facingRight: right,
                  interactive: widget.interactive,
                  hitInsetBottom: widget.hitInsetBottom,
                  startleToken: widget.startleToken,
                  love: widget.love,
                  positionSource: widget.positionSource,
                  beatOffset: widget.beatOffset,
                  onTap: widget.onTap,
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
/// it plays, sits when paused, runs to a sought position, jumps when the song
/// is skipped and shows a heart when the song is liked. Used by the mini
/// player and Now Playing.
///
/// With [full] it also dances exactly on the song's beat (tempo from the
/// catalog, else the tempo cache; position from the player), opens the chat
/// when tapped, and now and then says something about the song in a small
/// bubble (if "Microduck talks" is on).
class PlayerMicroduckStrip extends ConsumerStatefulWidget {
  final AudioPlayer player;
  final Song song;
  final double height;

  /// Now Playing: dance to the song's tempo, nap at night, react to taps,
  /// talk. The mini player passes false and just walks.
  final bool full;

  /// How solid it is drawn. The robot lays over the UI and never takes its
  /// room, so over text it is translucent and fades out at the [fadeEdges]
  /// (left and right) and [fadeTop].
  final double opacity;
  final bool fadeEdges;
  final bool fadeTop;

  /// Keeps the bottom of the robot's touch area off a bar it stands on.
  final double hitInsetBottom;

  const PlayerMicroduckStrip({
    super.key,
    required this.player,
    required this.song,
    this.height = 88,
    this.full = true,
    this.opacity = 1,
    this.fadeEdges = false,
    this.fadeTop = false,
    this.hitInsetBottom = 0,
  });

  @override
  ConsumerState<PlayerMicroduckStrip> createState() => _PlayerMicroduckStripState();
}

class _PlayerMicroduckStripState extends ConsumerState<PlayerMicroduckStrip> {
  /// One remark at a time, and not too often across songs.
  static DateTime _lastSpoke = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cooldown = Duration(minutes: 2);

  String? _bubble;
  String _bubbleFor = '';
  Timer? _speakTimer, _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleRemark();
  }

  @override
  void didUpdateWidget(PlayerMicroduckStrip old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) {
      _hide();
      _scheduleRemark();
    }
  }

  @override
  void dispose() {
    _speakTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  MicroduckFacts _facts() {
    final song = widget.song;
    final catalog = ref.read(catalogSongProvider(song.id));
    return MicroduckFacts(
      songId: song.id,
      title: song.title,
      composer: song.composer,
      film: catalog?.film,
      year: song.year,
      playCount: song.playCount,
      starred: song.starred,
      bpm: danceBpm(catalog?.bpm) ?? cachedBpm(song.id),
    );
  }

  void _scheduleRemark() {
    _speakTimer?.cancel();
    final now = DateTime.now();
    if (!widget.full || !microduckFeelsChatty(widget.song.id, now)) return;
    _speakTimer = Timer(const Duration(seconds: 9), () {
      if (!mounted || !ref.read(settingsProvider).microduckTalks) return;
      final playing = ref.read(playerProvider).isPlaying;
      final at = DateTime.now();
      if (!playing || at.difference(_lastSpoke) < _cooldown) return;
      final line = microduckComment(_facts(), at);
      if (line == null) return;
      _lastSpoke = at;
      setState(() {
        _bubble = line;
        _bubbleFor = widget.song.id;
      });
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 6), _hide);
    });
  }

  /// Blends the robot into what is behind it: translucent, with its edges
  /// dissolving rather than ending in a hard line.
  Widget _soften(Widget robot) {
    var w = robot;
    if (widget.fadeEdges || widget.fadeTop) {
      w = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) {
          final h = widget.fadeEdges
              ? const LinearGradient(
                  colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.14, 0.86, 1],
                ).createShader(r)
              : null;
          if (!widget.fadeTop) return h!;
          // Top fade only (edges handled by the robot staying on its track).
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
            stops: [0, 0.45, 1],
          ).createShader(r);
        },
        child: w,
      );
    }
    return widget.opacity < 1 ? Opacity(opacity: widget.opacity, child: w) : w;
  }

  void _hide() {
    _hideTimer?.cancel();
    if (mounted && _bubble != null) setState(() => _bubble = null);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider.select((s) => s.microduckEnabled));
    if (!enabled) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final song = widget.song;
    final full = widget.full;
    final total = song.duration * 1000;
    final catalog = full ? ref.watch(catalogSongProvider(song.id)) : null;
    final bpm = full ? (danceBpm(catalog?.bpm) ?? cachedBpm(song.id)) : null;
    return PlaybackPosition(
      player: widget.player,
      songId: song.id,
      resolution: const Duration(milliseconds: 500),
      builder: (context, pos) {
        final progress = total > 0 ? pos.inMilliseconds / total : 0.0;
        final robot = MicroduckStrip(
          progress: progress,
          playing: playing,
          bpm: bpm,
          danceOnBeat: full,
          sleepsAtNight: full,
          interactive: full,
          hitInsetBottom: widget.hitInsetBottom,
          sitWhenPaused: !full,
          enter: true,
          startleToken: song.id,
          love: song.starred,
          showTrack: false,
          height: widget.height,
          positionSource: full ? () => widget.player.position : null,
          beatOffset: catalog?.beatOffset ?? 0,
          onTap: full ? () => showMicroduckChat(context) : null,
        );
        // One robot on screen at a time: while the chat is open it is the
        // chat's.
        final strip = ValueListenableBuilder<bool>(
          valueListenable: microduckChatOpen,
          builder: (context, open, child) => open ? SizedBox(height: widget.height) : child!,
          child: _soften(robot),
        );
        final bubble = _bubble;
        if (bubble == null || _bubbleFor != song.id || microduckChatOpen.value) return strip;
        // The bubble sits on the free side of the robot, above its head
        // level, so it never reaches the controls below.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            strip,
            Positioned(
              top: 0,
              left: progress > 0.5 ? 0 : null,
              right: progress > 0.5 ? null : 0,
              child: _SpeechBubble(text: bubble, onDismiss: _hide),
            ),
          ],
        );
      },
    );
  }
}

/// A small dismissible speech bubble.
class _SpeechBubble extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;
  const _SpeechBubble({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Semantics(
        label: text,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
          ),
        ),
      ),
    );
  }
}

/// Marks the Now Playing scrubber, so the robot can stand on its track, and
/// the song's title, so it never stands in front of the first line.
final GlobalKey microduckTrackKey = GlobalKey(debugLabel: 'microduck track');
final GlobalKey microduckTitleKey = GlobalKey(debugLabel: 'microduck title');

/// True while the mini player has the robot on screen: any other robot (an
/// empty state's) then keeps to its drawing, so there is only ever one.
final ValueNotifier<bool> microduckMiniVisible = ValueNotifier(false);

/// Where the robot's feet sit on the scrubber, from the top of its box: the
/// top edge of the 6dp bar in the middle of the 32dp touch band.
const double kScrubberBarTop = 13;

/// The tallest the Now Playing robot is allowed to be, and the shortest it is
/// worth showing at.
const double kOverlayMaxHeight = 56, kOverlayMinHeight = 30;

/// How tall the robot may be when its feet are at [feetY] and the title's
/// first line ends at [titleBottom] (null: not measured). Zero means "no room:
/// leave it out" — better absent than covering the title.
double overlayHeight({required double feetY, double? titleBottom}) {
  if (titleBottom == null) return 44;
  final room = feetY - titleBottom;
  if (room < kOverlayMinHeight) return 0;
  return room > kOverlayMaxHeight ? kOverlayMaxHeight : room;
}

/// The robot on Now Playing: a layer over the whole screen, standing on the
/// scrubber's bar, taking no room from the layout. It measures the scrubber
/// and the title once the frame is laid out, stands with its feet on the top
/// of the bar, and is only as tall as the gap between the title's first line
/// and the bar allows; with no gap it is not shown at all. It fades out at
/// the top so it melts into what it stands in front of, and only its upper
/// part takes touches, so the bar keeps every touch.
class MicroduckScrubberOverlay extends ConsumerStatefulWidget {
  final AudioPlayer player;
  final Song song;

  const MicroduckScrubberOverlay({super.key, required this.player, required this.song});

  @override
  ConsumerState<MicroduckScrubberOverlay> createState() => _MicroduckScrubberOverlayState();
}

class _MicroduckScrubberOverlayState extends ConsumerState<MicroduckScrubberOverlay> {
  Rect? _track;
  double? _titleBottom;

  void _measure() {
    if (!mounted) return;
    final origin = context.findAncestorRenderObjectOfType<RenderStack>()?.localToGlobal(Offset.zero) ?? Offset.zero;
    Rect? track;
    final tb = microduckTrackKey.currentContext?.findRenderObject();
    if (tb is RenderBox && tb.attached && tb.hasSize) track = (tb.localToGlobal(Offset.zero) - origin) & tb.size;
    double? titleBottom;
    final ti = microduckTitleKey.currentContext?.findRenderObject();
    if (ti is RenderBox && ti.attached && ti.hasSize) titleBottom = (ti.localToGlobal(Offset.zero) - origin).dy + ti.size.height;
    final moved = track != _track || (titleBottom != null && _titleBottom != null && (titleBottom - _titleBottom!).abs() > 0.5) || (_titleBottom == null) != (titleBottom == null);
    if (moved) {
      setState(() {
        _track = track;
        _titleBottom = titleBottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final track = _track;
    if (track == null || !ref.watch(settingsProvider.select((s) => s.microduckEnabled))) {
      return const SizedBox.shrink();
    }
    final feet = track.top + kScrubberBarTop;
    final height = overlayHeight(feetY: feet, titleBottom: _titleBottom);
    if (height <= 0) return const SizedBox.shrink();
    return Positioned(
      left: track.left,
      width: track.width,
      // The painted feet sit 4.5% above the bottom of the robot's square.
      top: feet - height * 0.955,
      height: height,
      child: PlayerMicroduckStrip(
        player: widget.player,
        song: widget.song,
        height: height,
        opacity: 0.85,
        fadeTop: true,
        // The feet stand on the bar's top edge: keep touches off the bottom
        // of the robot, which sits right above the touch band.
        hitInsetBottom: height * 0.25,
      ),
    );
  }
}
