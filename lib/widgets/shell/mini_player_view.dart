import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../models/song.dart';
import '../../player/fitting_title.dart';
import '../../providers/player_provider.dart';
import '../../services/mini_player.dart';
import '../art/navi_icons.dart';
import 'desktop/player_bar.dart';
import 'mini_player_parts.dart';

// =============================================================================
// mini_player_view.dart — what the window shows in mini player mode.
//
// Two shapes of one idea: the cover is the window.
//   Strip (360 x 96)   the cover flush on the left, the song and its transport
//                      on the right, the scrubber along the bottom edge.
//   Square (360 x 360) the cover full-bleed, fading into its own tone where the
//                      title, the live lyric line, transport and scrubber sit;
//                      the window buttons appear when the pointer is over it.
// Drag it by any part that is not a control; double-click switches shape; the
// wheel changes the volume; Space, the arrows, L and Esc work from the keyboard.
// No glass, no shadow, no cards: one opaque ground.
// =============================================================================

/// Shows [child] (the whole app) normally and the mini player while
/// [MiniPlayer.active]. The app stays mounted underneath so nothing resets.
class MiniPlayerHost extends StatelessWidget {
  final Widget child;
  final MiniPlayer? controller;
  const MiniPlayerHost({super.key, required this.child, this.controller});

  @override
  Widget build(BuildContext context) {
    final mini = controller ?? MiniPlayer.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: mini.active,
      child: child,
      builder: (context, active, app) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: active,
            child: TickerMode(enabled: !active, child: app!),
          ),
          if (active) MiniPlayerView(onReturn: mini.exit, controller: mini),
        ],
      ),
    );
  }
}

class MiniPlayerView extends ConsumerStatefulWidget {
  final VoidCallback onReturn;
  final MiniPlayer? controller;
  const MiniPlayerView({super.key, required this.onReturn, this.controller});

  /// The strip's cover is as tall as the strip.
  static const double _bar = 96;

  /// Height of the title, lyric line, transport and scrubber on the square.
  static const double _zone = 150;

  /// A fixed-size window cannot grow with the system's text size; past this the
  /// text would push the controls out of it.
  static const double maxTextScale = 1.15;

  @override
  ConsumerState<MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends ConsumerState<MiniPlayerView> {
  late final MiniPlayer _mini = widget.controller ?? MiniPlayer.instance;
  final MiniVolume _volume = MiniVolume();
  final ValueNotifier<bool> _hover = ValueNotifier(false);
  final FocusNode _focus = FocusNode(debugLabel: 'MiniPlayer');

  @override
  void dispose() {
    _volume.dispose();
    _hover.dispose();
    _focus.dispose();
    super.dispose();
  }

  PlayerNotifier get _n => ref.read(playerProvider.notifier);

  void _seekBy(Duration d) {
    final p = _n.player;
    final to = p.position + d;
    p.seek(to < Duration.zero ? Duration.zero : to);
  }

  void _star() {
    final song = ref.read(playerProvider).currentSong;
    if (song != null) _n.toggleStar(song.id);
  }

  @override
  void initState() {
    super.initState();
    // The app underneath still holds the keyboard, so autofocus alone is
    // ignored: take it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final mq = MediaQuery.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));

    final body = ValueListenableBuilder<MiniMode>(
      valueListenable: _mini.mode,
      builder: (context, mode, _) => mode == MiniMode.bar
          ? _Strip(view: this, song: song)
          : _Square(view: this, song: song),
    );

    return MediaQuery(
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(
          maxScaleFactor: MiniPlayerView.maxTextScale,
        ),
      ),
      // The host sits in MaterialApp.builder, above the Navigator: nothing
      // there gives the tooltips an Overlay or the text a style (without a
      // Material it is drawn with the framework's yellow debug underline).
      child: Overlay.wrap(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): _n.togglePlay,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _seekBy(const Duration(seconds: -5)),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _seekBy(const Duration(seconds: 5)),
            const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
                _n.playPrev,
            const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
                _n.playNext,
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _volume.nudge(_n.player, 0.05),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _volume.nudge(_n.player, -0.05),
            const SingleActivator(LogicalKeyboardKey.keyL): _star,
            const SingleActivator(LogicalKeyboardKey.escape): widget.onReturn,
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
                  _volume.nudge(_n.player, e.scrollDelta.dy < 0 ? 0.05 : -0.05);
                }
              },
              child: MouseRegion(
                onEnter: (_) => _hover.value = true,
                onExit: (_) => _hover.value = false,
                child: Material(
                  color: t.bgBase,
                  child: _FadeIn(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MiniDragArea(mini: _mini, child: body),
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: MiniVolumeToast(level: _volume.toast),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window's first appearance: a 160 ms fade, none with reduced motion.
class _FadeIn extends StatelessWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  Widget build(BuildContext context) => context.motionFull
      ? TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: child,
          builder: (context, v, c) => Opacity(opacity: v, child: c),
        )
      : child;
}

// ── Controls shared by both shapes ───────────────────────────────────────────

/// Pin, shape and way back: the three window controls.
class _WindowButtons extends StatelessWidget {
  final MiniPlayer mini;
  final VoidCallback onReturn;
  const _WindowButtons({required this.mini, required this.onReturn});

  @override
  Widget build(BuildContext context) => MiniNoDrag(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: mini.pinned,
          builder: (context, pinned, _) => BarIconButton(
            icon: pinned ? NaviGlyph.pin : NaviGlyph.pinOff,
            tooltip: pinned ? 'Stop keeping on top' : 'Keep on top',
            active: pinned,
            onTap: mini.togglePinned,
          ),
        ),
        ValueListenableBuilder<MiniMode>(
          valueListenable: mini.mode,
          builder: (context, mode, _) => BarIconButton(
            icon: mode == MiniMode.bar ? NaviGlyph.photo : NaviGlyph.listView,
            tooltip: mode == MiniMode.bar ? 'Show the cover' : 'Show the strip',
            onTap: mini.toggleMode,
          ),
        ),
        BarIconButton(
          icon: NaviGlyph.expand,
          tooltip: 'Back to full player',
          onTap: onReturn,
        ),
      ],
    ),
  );
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final n = ref.read(playerProvider.notifier);
    return MiniNoDrag(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BarIconButton(
            icon: NaviGlyph.previous,
            tooltip: 'Previous (Ctrl+←)',
            size: 20,
            onTap: n.playPrev,
          ),
          const SizedBox(width: Space.xs),
          BarPlayButton(playing: playing, onTap: n.togglePlay),
          const SizedBox(width: Space.xs),
          BarIconButton(
            icon: NaviGlyph.next,
            tooltip: 'Next (Ctrl+→)',
            size: 20,
            onTap: n.playNext,
          ),
        ],
      ),
    );
  }
}

class _Star extends ConsumerWidget {
  final Song song;
  const _Star({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred = ref.watch(
      playerProvider.select((s) => s.starredIds.contains(song.id)),
    );
    return MiniNoDrag(
      child: BarIconButton(
        icon: NaviGlyph.star,
        filled: starred,
        active: starred,
        tooltip: starred ? 'Remove from Favorites (L)' : 'Favorite (L)',
        onTap: () => ref.read(playerProvider.notifier).toggleStar(song.id),
      ),
    );
  }
}

// ── Strip ────────────────────────────────────────────────────────────────────

class _Strip extends ConsumerWidget {
  final _MiniPlayerViewState view;
  final Song? song;
  const _Strip({required this.view, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = song;
    final lyric = s == null ? null : ref.watch(miniLyricLineProvider);
    final title = t.subheadline.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w600,
    );
    return Stack(
      children: [
        // The scrubber runs along the bottom edge under everything else.
        if (s != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: -8,
            height: 28,
            child: MiniNoDrag(
              child: DesktopSeekBar(song: s, showLabels: false, thickness: 3),
            ),
          ),
        Positioned.fill(
          child: Row(
            children: [
              MiniBarArt(song: s, size: MiniPlayerView._bar),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm,
                    Space.sm,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FittingTitle(
                              text: s?.title ?? 'Nothing playing',
                              style: title,
                            ),
                          ),
                          if (s != null) ...[
                            const SizedBox(width: Space.sm),
                            MiniClock(
                              song: s,
                              style: t.caption2.copyWith(color: t.textMuted),
                            ),
                          ],
                        ],
                      ),
                      if (s != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: SizedBox(
                            height: 17,
                            child: MiniFadingLine(
                              text: lyric ?? s.artist,
                              style: lyric == null
                                  ? t.caption1
                                  : t.caption1.copyWith(color: t.textPrimary),
                            ),
                          ),
                        ),
                      const Spacer(),
                      Row(
                        children: [
                          if (s != null) const _Transport(),
                          const Spacer(),
                          if (s != null) _Star(song: s),
                          _WindowButtons(
                            mini: view._mini,
                            onReturn: view.widget.onReturn,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Square ───────────────────────────────────────────────────────────────────

class _Square extends ConsumerWidget {
  final _MiniPlayerViewState view;
  final Song? song;
  const _Square({required this.view, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = song;
    final lyric = s == null ? null : ref.watch(miniLyricLineProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        MiniCoverArt(
          song: s,
          size: MiniPlayer.coverSize,
          zone: MiniPlayerView._zone,
        ),
        // The window controls show with the pointer (or the keyboard) and
        // rest otherwise, so the cover is the whole picture.
        Positioned(
          top: 6,
          left: 6,
          right: 6,
          child: _Reveal(
            hover: view._hover,
            child: Align(
              alignment: Alignment.centerRight,
              child: _WindowButtons(
                mini: view._mini,
                onReturn: view.widget.onReturn,
              ),
            ),
          ),
        ),
        Positioned(
          left: Space.lg,
          right: Space.lg,
          bottom: Space.sm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittingTitle(
                text: s?.title ?? 'Nothing playing',
                style: t.title3.copyWith(color: t.textPrimary),
              ),
              if (s != null) ...[
                Text(
                  s.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.subheadline.copyWith(color: t.textSecondary),
                ),
                SizedBox(
                  height: 24,
                  child: MiniFadingLine(
                    text: lyric ?? '',
                    style: t.subheadline.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      children: [
                        _Star(song: s),
                        const Spacer(),
                      ],
                    ),
                    const _Transport(),
                  ],
                ),
                MiniNoDrag(child: DesktopSeekBar(song: s)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades [child] in while the pointer is over the window or a control has
/// keyboard focus; it keeps its place and stays reachable either way.
class _Reveal extends StatelessWidget {
  final ValueListenable<bool> hover;
  final Widget child;
  const _Reveal({required this.hover, required this.child});

  @override
  Widget build(BuildContext context) {
    final full = context.motionFull;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return ValueListenableBuilder<bool>(
            valueListenable: hover,
            builder: (context, h, c) => AnimatedOpacity(
              opacity: h || focused ? 1 : 0,
              duration: full
                  ? const Duration(milliseconds: 140)
                  : Duration.zero,
              child: c,
            ),
            child: child,
          );
        },
      ),
    );
  }
}
