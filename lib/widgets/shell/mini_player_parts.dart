import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../lyrics/controllers/lyrics_controller.dart';
import '../../models/song.dart';
import '../../player/artwork.dart';
import '../../player/full_bleed_art.dart';
import '../../player/cover_quality.dart';
import '../../player/playback_progress.dart';
import '../../player/player_controls.dart' show formatClock;
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/mini_player.dart';
import '../art/navi_icons.dart';

// =============================================================================
// mini_player_parts.dart — the small pieces of the mini player window.
//
// The live lyric line, the cover that slides on a track change, the elapsed
// clock, the volume toast and the layer that drags the window. Each one
// rebuilds only for what it shows.
// =============================================================================

/// The synced lyric line sung right now, or null (no lyrics, plain lyrics,
/// before the first line, an instrumental gap). Only changes when the line does.
final miniLyricLineProvider = Provider.autoDispose<String?>((ref) {
  final line = ref.watch(
    lyricsControllerProvider.select((s) {
      final lyrics = s.lyrics;
      final i = s.activeLineIndex;
      if (s.status != LyricsStatus.synced ||
          lyrics == null ||
          i < 0 ||
          i >= lyrics.lines.length) {
        return '';
      }
      return lyrics.lines[i].text.trim();
    }),
  );
  return line.isEmpty ? null : line;
});

/// A line of text that cross-fades (and rises a few px) when it changes.
class MiniFadingLine extends StatelessWidget {
  final String text;
  final TextStyle style;
  const MiniFadingLine({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final full = context.motionFull;
    return AnimatedSwitcher(
      duration: full ? const Duration(milliseconds: 200) : Duration.zero,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Align(
        key: ValueKey(text),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// Slides the old cover out to the left and the new one in from the right.
/// With reduced motion the cover just changes.
class MiniArtSwitcher extends StatelessWidget {
  final String songKey;
  final Widget child;
  const MiniArtSwitcher({
    super.key,
    required this.songKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final full = context.motionFull;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: full ? const Duration(milliseconds: 260) : Duration.zero,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, anim) {
          final incoming = c.key == ValueKey(songKey);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: Offset(incoming ? 0.18 : -0.18, 0),
                end: Offset.zero,
              ).animate(anim),
              child: c,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(songKey), child: child),
      ),
    );
  }
}

/// The strip's cover: a square the height of the window, flush with its edge.
class MiniBarArt extends ConsumerWidget {
  final Song? song;
  final double size;
  const MiniBarArt({super.key, required this.song, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = song;
    if (s == null) {
      return SizedBox(
        width: size,
        height: size,
        child: ColoredBox(color: t.bgElevated),
      );
    }
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(s.coverArt);
    return MiniArtSwitcher(
      songKey: s.id,
      child: CoverImage(
        url: url,
        cacheKey: coverCacheKey(s),
        width: size,
        height: size,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
  }
}

/// The square's cover: full-bleed, fading into the cover's own deep tone
/// where the song and transport sit.
class MiniCoverArt extends ConsumerWidget {
  final Song? song;
  final Size size;

  /// Height of the block of text and controls that sits on the fade.
  final double zone;
  const MiniCoverArt({
    super.key,
    required this.song,
    required this.size,
    required this.zone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = song;
    if (s == null) {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: ColoredBox(color: t.bgElevated),
      );
    }
    final request = nowPlayingCoverRequest(
      ref.read(subsonicServiceProvider),
      s,
      size.width,
      MediaQuery.devicePixelRatioOf(context),
    );
    final tint =
        ref.watch(
          coverPaletteProvider(s.coverArt).select((a) => a.value?.deep),
        ) ??
        t.bgBase;
    return MiniArtSwitcher(
      songKey: s.id,
      child: FullBleedCover(
        request: request,
        width: size.width,
        height: size.height,
        tint: tint,
        scrimHeight: 56,
        zone: zone,
      ),
    );
  }
}

/// "1:00 / 4:00", tabular, redrawn at the scrubber's pace.
class MiniClock extends ConsumerWidget {
  final Song song;
  final TextStyle style;
  const MiniClock({super.key, required this.song, required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier).player;
    return RepaintBoundary(
      child: PlaybackProgressBuilder(
        player: player,
        song: song,
        resolution: const Duration(milliseconds: 500),
        builder: (context, p) => Text(
          '${formatClock(p.position)} / ${formatClock(p.total)}',
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// A pill that shows the volume for a moment after the wheel changes it.
class MiniVolumeToast extends StatelessWidget {
  /// 0..1 while shown, null when hidden.
  final ValueListenable<double?> level;
  const MiniVolumeToast({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final full = context.motionFull;
    return IgnorePointer(
      child: ValueListenableBuilder<double?>(
        valueListenable: level,
        builder: (context, v, _) => AnimatedOpacity(
          opacity: v == null ? 0 : 1,
          duration: full ? const Duration(milliseconds: 140) : Duration.zero,
          child: v == null
              ? const SizedBox.shrink()
              : Semantics(
                  liveRegion: true,
                  label: 'Volume ${(v * 100).round()}%',
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    decoration: BoxDecoration(
                      color: t.bgElevated,
                      borderRadius: BorderRadius.circular(Radii.capsule),
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NaviIcon(
                            v <= 0.001
                                ? NaviGlyph.speakerOff
                                : (v < 0.5
                                      ? NaviGlyph.speakerLow
                                      : NaviGlyph.speaker),
                            size: 16,
                            color: t.textPrimary,
                          ),
                          const SizedBox(width: Space.sm),
                          SizedBox(
                            width: 72,
                            height: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.fill,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: v.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: t.textPrimary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          Text(
                            '${(v * 100).round()}',
                            style: t.footnote.copyWith(
                              color: t.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Drags the window from anywhere that is not a [MiniNoDrag] control (the mini
/// window has no title bar), and switches shape on a double-click. It wraps the
/// content, so the cover and the text cannot swallow the drag, and it watches
/// raw pointers instead of joining the gesture arena, so buttons under it are
/// neither delayed by a double-tap nor lose a click to a shaky hand.
/// After a drag, the new corner is remembered.
class MiniDragArea extends StatefulWidget {
  final MiniPlayer mini;
  final Widget child;
  const MiniDragArea({super.key, required this.mini, required this.child});

  /// How far the pointer travels before a press becomes a window drag.
  static const double slop = 3;

  @override
  State<MiniDragArea> createState() => _MiniDragAreaState();
}

class _MiniDragAreaState extends State<MiniDragArea> {
  /// The press that may still become a drag or a click.
  int? _pointer;
  Offset _from = Offset.zero;

  /// Set after one click, while a second one would make it a double-click.
  Timer? _second;
  Offset _first = Offset.zero;

  void _down(PointerDownEvent e) {
    // Controls are deeper in the tree, so they have claimed the press already.
    if (MiniNoDrag._claimed.remove(e.pointer)) return;
    if (e.buttons != kPrimaryButton) return;
    _pointer = e.pointer;
    _from = e.position;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer ||
        (e.position - _from).distance < MiniDragArea.slop) {
      return;
    }
    _pointer = null;
    _forgetClick();
    _drag();
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_second != null && (e.position - _first).distance < kDoubleTapSlop) {
      _forgetClick();
      widget.mini.toggleMode();
      return;
    }
    _forgetClick();
    _first = e.position;
    _second = Timer(kDoubleTapTimeout, () => _second = null);
  }

  void _forgetClick() {
    _second?.cancel();
    _second = null;
  }

  Future<void> _drag() async {
    try {
      await windowManager.startDragging();
      await widget.mini.rememberPosition();
    } catch (_) {
      // No window (tests, a failed call): there is nothing to move.
    }
  }

  @override
  void dispose() {
    _second?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (e) {
      if (e.pointer == _pointer) _pointer = null;
    },
    child: widget.child,
  );
}

/// Marks a control inside a [MiniDragArea]: a press that starts on it never
/// moves the window or counts toward a double-click.
class MiniNoDrag extends StatelessWidget {
  final Widget child;
  const MiniNoDrag({super.key, required this.child});

  static final Set<int> _claimed = {};

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: (e) => _claimed.add(e.pointer), child: child);
}

/// Keeps the volume toast and its timer, and nudges the player's volume.
class MiniVolume {
  final ValueNotifier<double?> toast = ValueNotifier(null);
  Timer? _timer;

  /// Changes the volume by [delta] (0.05 = one wheel notch) and shows it.
  void nudge(AudioPlayer player, double delta) {
    final v = (player.volume + delta).clamp(0.0, 1.0);
    player.setVolume(v);
    toast.value = v;
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 1300),
      () => toast.value = null,
    );
  }

  void dispose() {
    _timer?.cancel();
    toast.dispose();
  }
}
