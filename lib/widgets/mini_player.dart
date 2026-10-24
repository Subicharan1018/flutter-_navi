import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/hive_boxes.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/player_controls.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../utils/platform_utils.dart';
import 'mascot/microduck_strip.dart';
import 'ui/ion.dart';

/// The floating mini player: a solid capsule in the album's colour (so the
/// song you're hearing tints the bottom of every screen), with the cover,
/// title, play/pause and next, and a hairline of progress under the title.
///
/// Swipe sideways to skip (the contents follow the finger), swipe up or tap
/// to open Now Playing.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  static const double height = 58;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  static const _hintSeenKey = 'mini_player_hint_seen';

  late final AnimationController _dx = AnimationController.unbounded(vsync: this);
  bool _skipping = false;

  /// First run only: once the first song appears, the capsule's contents
  /// slide a little and spring back, the way iOS hints that a row swipes.
  /// No text, no tooltip; it happens once and never again.
  bool _hintSeen = _readHintSeen();
  Timer? _nudge;
  static const Duration _nudgeDelay = Duration(milliseconds: 1400);
  static const double _nudgeDistance = 34;

  static bool _readHintSeen() {
    try {
      return HiveBoxes.prefs.get(_hintSeenKey) == true;
    } catch (_) {
      return true;
    }
  }

  void _retireHint() {
    if (_hintSeen || !mounted) return;
    _hintSeen = true;
    try {
      HiveBoxes.prefs.put(_hintSeenKey, true);
    } catch (_) {}
  }

  void _scheduleNudge() {
    if (_hintSeen || _nudge != null) return;
    _nudge = Timer(_nudgeDelay, () async {
      if (!mounted || _hintSeen || _dx.value != 0) return;
      _retireHint();
      if (!context.motionFullNow) return;
      await _dx.animateTo(-_nudgeDistance, duration: Motion.standard, curve: Curves.easeOutCubic);
      if (!mounted) return;
      _dx.animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 18),
        _dx.value,
        0,
        0,
      ));
    });
  }

  @override
  void dispose() {
    _nudge?.cancel();
    _dx.dispose();
    super.dispose();
  }

  void _open() {
    if (PlatformUtils.prefersSidebarNavigation) return; // desktop uses the bottom bar
    HapticFeedback.selectionClick();
    _retireHint();
    openNowPlaying(context);
  }

  Future<void> _endSwipe(DragEndDetails d, double width) async {
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _dx.value;
    final go = !_skipping && (dx.abs() > width * 0.28 || v.abs() > 800);
    if (go) {
      _skipping = true;
      HapticFeedback.lightImpact();
      _retireHint();
      final n = ref.read(playerProvider.notifier);
      unawaited((dx < 0 || v < -800 ? n.playNext() : n.playPrev()).whenComplete(() {
        Future.delayed(const Duration(milliseconds: 250), () => _skipping = false);
      }));
    }
    _dx.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 380, damping: 30),
      dx,
      0,
      v / 1000,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final palette = ref.watch(albumPaletteProvider);
    final notifier = ref.read(playerProvider.notifier);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final ground = palette.ground;
    final duck = ref.watch(settingsProvider.select((s) => s.microduckEnabled));

    _scheduleNudge();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: Semantics(
        container: true,
        label: 'Now playing: ${song.title} by ${song.artist}. Opens the player.',
        child: LayoutBuilder(builder: (context, c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -250) _open();
            },
            onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
            onHorizontalDragEnd: (d) => _endSwipe(d, c.maxWidth),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              height: MiniPlayer.height,
              decoration: BoxDecoration(
                color: ground,
                borderRadius: BorderRadius.circular(Radii.capsule),
                border: Border.all(color: Color.lerp(ground, Colors.white, 0.12)!, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _dx,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_dx.value * 0.6, 0),
                      child: Opacity(
                        opacity: (1 - (_dx.value.abs() / (c.maxWidth * 0.6))).clamp(0.25, 1.0),
                        child: child,
                      ),
                    ),
                    child: _Content(song: song, url: url, ground: ground, lifted: duck),
                  ),
                  // Walks the progress hairline below; the text above is
                  // lifted a few pixels to give it room.
                  if (duck)
                    Positioned(
                      left: _Content.textInset,
                      right: _Content.controlsInset,
                      bottom: 6,
                      child: PlayerMicroduckStrip(
                        player: notifier.player,
                        song: song,
                        height: 14,
                        color: Color.lerp(ground, Colors.white, 0.9),
                        full: false,
                      ),
                    ),
                  Positioned(
                    right: Space.sm,
                    top: 0,
                    bottom: 2,
                    child: Row(
                      children: [
                        _MiniPlayPause(playing: playing, onTap: notifier.togglePlay),
                        GlyphButton(
                          size: 44,
                          semanticLabel: 'Next',
                          onTap: notifier.playNext,
                          child: const IonIcon(Ion.playForward, color: Colors.white, size: 26),
                        ),
                      ],
                    ),
                  ),
                  // Inset above the capsule's base so the curve never clips
                  // it: it runs under the title, from the cover to the controls.
                  Positioned(
                    left: _Content.textInset,
                    right: _Content.controlsInset,
                    bottom: 7,
                    child: _MiniProgress(player: notifier.player, song: song, ground: ground),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  static const double _coverInset = 8;
  static const double _cover = 42;

  /// Where the text starts, and how much room the trailing controls take.
  static const double textInset = _coverInset + _cover + Space.md;
  static const double controlsInset = 108;

  final Song song;
  final String url;
  final Color ground;

  /// Makes room under the text for the mascot.
  final bool lifted;
  const _Content({required this.song, required this.url, required this.ground, this.lifted = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // Round cover so it nests in the capsule's end like iOS 26's mini player.
    final cover = ClipOval(
      child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: _cover, height: _cover, cacheWidth: 126),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(_coverInset, 0, controlsInset, lifted ? 15 : 2),
      child: Row(
        children: [
          // Shared-element flight into the Now Playing cover (phones only;
          // desktop shows two covers at once and a duplicate tag would clash).
          PlatformUtils.isDesktop ? cover : Hero(tag: 'np_cover', child: cover),
          const SizedBox(width: Space.md),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Column(
                key: ValueKey(song.id),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.callout.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.footnote.copyWith(color: Color.lerp(ground, Colors.white, 0.72)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayPause extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _MiniPlayPause({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlyphButton(
      size: 48,
      semanticLabel: playing ? 'Pause' : 'Play',
      onTap: onTap,
      child: PlayPauseGlyph(playing: playing, size: 28, color: Colors.white),
    );
  }
}

/// 2px progress hairline in solid steps of the capsule colour; its own
/// repaint boundary so position ticks never rebuild the card.
class _MiniProgress extends StatelessWidget {
  final AudioPlayer player;
  final Song song;
  final Color ground;
  const _MiniProgress({required this.player, required this.song, required this.ground});

  @override
  Widget build(BuildContext context) {
    final total = song.duration * 1000;
    final track = Color.lerp(ground, Colors.white, 0.18)!;
    final fill = Color.lerp(ground, Colors.white, 0.9)!;
    return RepaintBoundary(
      child: PlaybackPosition(
        player: player,
        songId: song.id,
        resolution: const Duration(milliseconds: 500),
        builder: (context, pos) {
          final f = total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              height: 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: track),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: f,
                    child: ColoredBox(color: fill),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
