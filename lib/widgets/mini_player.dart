import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/player_controls.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../utils/platform_utils.dart';

/// The floating mini player: a solid card in the album's colour (so the
/// song you're hearing tints the bottom of every screen), with the cover,
/// title, play/pause and next, and a hairline of progress along its base.
///
/// Swipe sideways to skip (the contents follow the finger), swipe up or tap
/// to open Now Playing.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this);
  bool _skipping = false;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _open() {
    if (PlatformUtils.prefersSidebarNavigation) return; // desktop uses the bottom bar
    HapticFeedback.selectionClick();
    openNowPlaying(context);
  }

  Future<void> _endSwipe(DragEndDetails d, double width) async {
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _dx.value;
    final go = !_skipping && (dx.abs() > width * 0.28 || v.abs() > 800);
    if (go) {
      _skipping = true;
      HapticFeedback.lightImpact();
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
              height: 60,
              decoration: BoxDecoration(
                color: Color.lerp(palette.base, Colors.black, 0.12),
                borderRadius: BorderRadius.circular(Radii.sheet - 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
                ],
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
                    child: _Content(song: song, url: url),
                  ),
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 2,
                    child: Row(
                      children: [
                        _MiniPlayPause(playing: playing, onTap: notifier.togglePlay),
                        GlyphButton(
                          size: 44,
                          semanticLabel: 'Next',
                          onTap: notifier.playNext,
                          child: const Icon(CupertinoIcons.forward_fill, color: Colors.white, size: 24),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 0,
                    child: _MiniProgress(player: notifier.player, song: song),
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
  final Song song;
  final String url;
  const _Content({required this.song, required this.url});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.cover),
      child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: 44, height: 44, cacheWidth: 132),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 104, 2),
      child: Row(
        children: [
          // Shared-element flight into the Now Playing cover (phones only;
          // desktop shows two covers at once and a duplicate tag would clash).
          PlatformUtils.isDesktop ? cover : Hero(tag: 'np_cover', child: cover),
          const SizedBox(width: 11),
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
                    style: t.subheadline.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.footnote.copyWith(color: Colors.white.withValues(alpha: 0.72)),
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

class _MiniPlayPause extends StatefulWidget {
  final bool playing;
  final VoidCallback onTap;
  const _MiniPlayPause({required this.playing, required this.onTap});

  @override
  State<_MiniPlayPause> createState() => _MiniPlayPauseState();
}

class _MiniPlayPauseState extends State<_MiniPlayPause> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(_MiniPlayPause old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) widget.playing ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlyphButton(
      size: 48,
      semanticLabel: widget.playing ? 'Pause' : 'Play',
      onTap: widget.onTap,
      child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _c, color: Colors.white, size: 30),
    );
  }
}

/// 2px progress hairline; its own repaint boundary so position ticks never
/// rebuild the card.
class _MiniProgress extends StatelessWidget {
  final AudioPlayer player;
  final Song song;
  const _MiniProgress({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final total = song.duration * 1000;
    return RepaintBoundary(
      child: PlaybackPosition(
        player: player,
        songId: song.id,
        resolution: const Duration(milliseconds: 500),
        builder: (context, pos) {
          final f = total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
          return SizedBox(
            height: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0x33FFFFFF)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: f,
                  child: const ColoredBox(color: Color(0xE6FFFFFF)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
