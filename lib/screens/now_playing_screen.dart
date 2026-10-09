import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/artwork_field.dart';
import '../player/lyrics_pane.dart';
import '../player/now_playing_style.dart';
import '../player/player_controls.dart';
import '../player/queue_pane.dart';
import '../player/sleep_timer.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/platform_utils.dart';
import '../widgets/desktop_dialogs.dart';
import '../widgets/options_menu.dart';

// =============================================================================
// Opening the player
// =============================================================================

/// Opens Now Playing: an interactive sheet on phones, a full-window fade on
/// desktop.
void openNowPlaying(BuildContext context) {
  final wide = PlatformUtils.isDesktop &&
      MediaQuery.sizeOf(context).width >= PlatformUtils.kDesktopBreakpoint;
  Navigator.of(context, rootNavigator: true).push(
    wide
        ? PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (_, _, _) => const NowPlayingScreen(),
            transitionsBuilder: (_, a, _, child) => FadeTransition(
              opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
              child: ScaleTransition(
                scale: Tween(begin: 1.03, end: 1.0)
                    .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                child: child,
              ),
            ),
          )
        : NowPlayingRoute(),
  );
}

/// A full-screen sheet that the listener can drag down from anywhere on the
/// player. The drag drives the route's own controller, so letting go
/// continues from exactly where the finger left it — no jump between the
/// gesture and the dismiss animation.
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute() : super(fullscreenDialog: true);

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get opaque => true;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 440);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  bool _dragging = false;

  void dragStart() {
    if (_dragging || controller == null) return;
    _dragging = true;
    navigator?.didStartUserGesture();
  }

  void dragUpdate(double dy, double height) {
    if (!_dragging) return;
    controller!.value = (controller!.value - dy / height).clamp(0.0, 1.0);
  }

  void dragEnd(double velocity, double height) {
    if (!_dragging) return;
    _dragging = false;
    final offset = (1 - controller!.value) * height;
    // Apple's momentum projection: where would this flick come to rest?
    const d = 0.998;
    final projected = offset + (velocity / 1000) * d / (1 - d);
    final dismiss = projected > height * 0.42 || velocity > 1100;
    if (dismiss) {
      navigator?.pop();
    } else {
      controller!.forward();
    }
    void finish(AnimationStatus s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        navigator?.didStopUserGesture();
        controller?.removeStatusListener(finish);
      }
    }

    if (controller!.isAnimating) {
      controller!.addStatusListener(finish);
    } else {
      navigator?.didStopUserGesture();
    }
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> a, Animation<double> b) =>
      const NowPlayingScreen();

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final linear = navigator?.userGestureInProgress ?? false;
    final curved = linear
        ? animation
        : CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

// =============================================================================
// Screen
// =============================================================================

enum _Pane { none, lyrics, queue }

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key, this.initialImageUrl});

  /// Kept for call-site compatibility; artwork now comes from the repository.
  final String? initialImageUrl;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with SingleTickerProviderStateMixin {
  _Pane _pane = _Pane.none;
  _Pane _shownPane = _Pane.lyrics; // what the pane slot renders (kept during close)
  late final AnimationController _paneAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    reverseDuration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _paneAnim.dispose();
    super.dispose();
  }

  void _togglePane(_Pane p) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_pane == p) {
        _pane = _Pane.none;
        _paneAnim.reverse();
      } else {
        _pane = p;
        _shownPane = p;
        _paneAnim.forward();
      }
    });
  }

  void _closePane() {
    if (_pane == _Pane.none) return;
    setState(() => _pane = _Pane.none);
    _paneAnim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.expand());
    }
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final art = ref.watch(nowPlayingArtworkProvider);
    final living = ref.watch(settingsProvider.select((s) => s.fluidBgEnabled));
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900 && size.width > size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: _pane == _Pane.none || wide,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closePane();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _pane != _Pane.none && !wide ? _closePane() : Navigator.maybePop(context),
          },
          child: Focus(
            autofocus: true,
            child: NowPlayingStyleScope(
              style: NowPlayingStyle.onArtwork,
              child: Scaffold(
                backgroundColor: art?.palette.deep ?? AlbumPalette.fallback.deep,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    ArtworkField(
                      art: art,
                      playing: playing && living,
                      dim: wide ? 0.55 : (_pane == _Pane.none ? 0 : 1),
                    ),
                    if (wide)
                      _WideLayout(song: song, playing: playing)
                    else
                      SafeArea(
                        child: _PhoneLayout(
                          song: song,
                          playing: playing,
                          pane: _pane,
                          shownPane: _shownPane,
                          paneAnim: _paneAnim,
                          onTogglePane: _togglePane,
                          onClosePane: _closePane,
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

// =============================================================================
// Phone layout
// =============================================================================

class _PhoneLayout extends ConsumerWidget {
  final Song song;
  final bool playing;
  final _Pane pane;
  final _Pane shownPane;
  final AnimationController paneAnim;
  final ValueChanged<_Pane> onTogglePane;
  final VoidCallback onClosePane;

  const _PhoneLayout({
    required this.song,
    required this.playing,
    required this.pane,
    required this.shownPane,
    required this.paneAnim,
    required this.onTogglePane,
    required this.onClosePane,
  });

  NowPlayingRoute? _route(BuildContext context) {
    final r = ModalRoute.of(context);
    return r is NowPlayingRoute ? r : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    final route = _route(context);
    final height = MediaQuery.sizeOf(context).height;

    // Vertical drag anywhere outside the scrolling panes dismisses the sheet.
    Widget dismissible(Widget child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: route == null ? null : (_) => route.dragStart(),
          onVerticalDragUpdate: route == null ? null : (d) => route.dragUpdate(d.delta.dy, height),
          onVerticalDragEnd: route == null ? null : (d) => route.dragEnd(d.velocity.pixelsPerSecond.dy, height),
          onVerticalDragCancel: route == null ? null : () => route.dragEnd(0, height),
          child: child,
        );

    return Column(
      children: [
        dismissible(_Grabber(onTap: () => Navigator.maybePop(context))),
        Expanded(
          child: _Stage(
            song: song,
            playing: playing,
            pane: pane,
            shownPane: shownPane,
            paneAnim: paneAnim,
            onClosePane: onClosePane,
            dismissible: dismissible,
            onNext: notifier.playNext,
            onPrevious: notifier.playPrev,
          ),
        ),
        dismissible(
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
            child: Column(
              children: [
                const _RemoteDeviceBanner(),
                Scrubber(player: notifier.player, song: song),
                const SizedBox(height: 6),
                TransportControls(
                  playing: playing,
                  onPlayPause: notifier.togglePlay,
                  onPrevious: notifier.playPrev,
                  onNext: notifier.playNext,
                ),
                const SizedBox(height: 10),
                VolumeBar(player: notifier.player),
                const SizedBox(height: 10),
                _BottomRow(pane: pane, onTogglePane: onTogglePane),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The region above the controls. In player mode it holds the big cover and
/// the title; when Lyrics or Queue open, cover and title fly into a header
/// row and the pane rises into the space they left — one continuous motion.
class _Stage extends StatefulWidget {
  final Song song;
  final bool playing;
  final _Pane pane;
  final _Pane shownPane;
  final AnimationController paneAnim;
  final VoidCallback onClosePane;
  final Widget Function(Widget) dismissible;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const _Stage({
    required this.song,
    required this.playing,
    required this.pane,
    required this.shownPane,
    required this.paneAnim,
    required this.onClosePane,
    required this.dismissible,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  static const double _headerArt = 60;
  static const double _headerTop = 6;

  // Horizontal swipe on the cover: tracks the finger, skips past a threshold,
  // springs home otherwise.
  late final AnimationController _swipe = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  void _swipeEnd(DragEndDetails d, double width) {
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _swipe.value;
    final go = dx.abs() > width * 0.22 || v.abs() > 700;
    if (go) {
      HapticFeedback.lightImpact();
      (dx < 0 || v < -700) ? widget.onNext() : widget.onPrevious();
    }
    _swipe.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 320, damping: 26),
      dx,
      0,
      v / 1000,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        const titleH = 58.0, gap = 22.0;
        final artSize = math.min(w - 56, h - titleH - gap - 12).clamp(140.0, 520.0);
        final groupH = artSize + gap + titleH;
        final top0 = math.max(4.0, (h - groupH) * 0.3);
        final big = Rect.fromLTWH((w - artSize) / 2, top0, artSize, artSize);
        const small = Rect.fromLTWH(20, _headerTop, _headerArt, _headerArt);

        return AnimatedBuilder(
          animation: Listenable.merge([widget.paneAnim, _swipe]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(widget.paneAnim.value);
            final artRect = Rect.lerp(big, small, t)!;
            final titleLeft = _lerp(28, small.right + 14, t);
            final titleTop = _lerp(big.bottom + gap, _headerTop + 4, t);
            final titleScale = _lerp(1, 0.8, t);
            final paneTop = small.bottom + 12;
            final paneT = Curves.easeOutCubic.transform(((widget.paneAnim.value - 0.25) / 0.75).clamp(0.0, 1.0));
            final inPlayer = widget.pane == _Pane.none && widget.paneAnim.value == 0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Pane — under the header, rising as the cover leaves.
                if (widget.paneAnim.value > 0)
                  Positioned.fill(
                    top: paneTop,
                    child: Opacity(
                      opacity: paneT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - paneT) * 28),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          child: widget.shownPane == _Pane.queue
                              ? QueuePane(key: const ValueKey('queue'), style: NowPlayingStyle.onArtwork)
                              : const LyricsPane(key: ValueKey('lyrics'), style: NowPlayingStyle.onArtwork),
                        ),
                      ),
                    ),
                  ),

                // Background drag target in player mode (dismiss gesture).
                if (inPlayer) Positioned.fill(child: widget.dismissible(const SizedBox.expand())),

                // Cover.
                Positioned.fromRect(
                  rect: artRect.shift(Offset(_swipe.value * (1 - t), 0)),
                  child: GestureDetector(
                    onTap: widget.pane != _Pane.none ? widget.onClosePane : null,
                    onHorizontalDragUpdate: inPlayer ? (d) => _swipe.value += d.delta.dx : null,
                    onHorizontalDragEnd: inPlayer ? (d) => _swipeEnd(d, w) : null,
                    child: widget.dismissible(
                      _Cover(
                        song: widget.song,
                        size: artRect.width,
                        radius: _lerp(12, 7, t),
                        // Apple's signature: the cover recedes while paused.
                        scale: reduce ? 1 : _lerp(widget.playing ? 1 : 0.84, 1, t),
                        tilt: inPlayer ? (_swipe.value / w).clamp(-0.4, 0.4) : 0,
                      ),
                    ),
                  ),
                ),

                // Title block.
                Positioned(
                  left: titleLeft,
                  top: titleTop,
                  width: (w - titleLeft - 12) / titleScale,
                  child: Transform.scale(
                    scale: titleScale,
                    alignment: Alignment.topLeft,
                    child: _TitleRow(song: widget.song, compact: t > 0.5),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _Grabber extends StatelessWidget {
  final VoidCallback onTap;
  const _Grabber({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close player',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 30,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Cover
// =============================================================================

class _Cover extends ConsumerWidget {
  final Song song;
  final double size;
  final double radius;
  final double scale;
  final double tilt; // -1..1 while swiping

  const _Cover({required this.song, required this.size, required this.radius, required this.scale, this.tilt = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final deep = ref.watch(albumPaletteProvider).deep;
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 560),
      // Grows with a little overshoot (it "lands" when music starts),
      // recedes without one.
      curve: scale >= 1 ? Curves.easeOutBack : Curves.easeOutCubic,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(tilt * 0.35),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(deep, Colors.black, 0.4)!.withValues(alpha: 0.55),
                blurRadius: size * 0.12,
                offset: Offset(0, size * 0.05),
              ),
            ],
          ),
          child: Hero(
            tag: 'np_cover',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                child: CoverImage(
                  key: ValueKey(song.id),
                  url: url,
                  cacheKey: coverCacheKey(song),
                  width: size,
                  height: size,
                  cacheWidth: 1000,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Title row — title, artist, favourite, more
// =============================================================================

class _TitleRow extends ConsumerWidget {
  final Song song;
  final bool compact;
  const _TitleRow({required this.song, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final titleStyle = naviText(22, FontWeight.w700, Colors.white);
    final artistStyle = naviText(19, FontWeight.w500, Colors.white.withValues(alpha: 0.68));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 28, child: _FittingTitle(text: song.title, style: titleStyle)),
              const SizedBox(height: 2),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: artistStyle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GlassCircleButton(
          icon: starred ? Icons.star_rounded : Icons.star_outline_rounded,
          semanticLabel: starred ? 'Remove from favourites' : 'Add to favourites',
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(playerProvider.notifier).toggleStar(song.id);
          },
        ),
        GlassCircleButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'More options',
          onTap: () => _showMore(context, song),
        ),
      ],
    );
  }
}

/// Static when it fits; a slow marquee with long pauses when it doesn't,
/// so a long Tamil film title is readable without truncation.
class _FittingTitle extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _FittingTitle({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final overflows = tp.width > c.maxWidth;
      tp.dispose();
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!overflows || reduce) {
        return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
      }
      return Marquee(
        text: text,
        style: style,
        blankSpace: 48,
        velocity: 32,
        startAfter: const Duration(seconds: 2),
        pauseAfterRound: const Duration(seconds: 3),
        fadingEdgeStartFraction: 0.04,
        fadingEdgeEndFraction: 0.1,
        showFadingOnlyWhenScrolling: true,
      );
    });
  }
}

void _showMore(BuildContext context, Song song) {
  showPlatformSheet(
    context: context,
    title: song.title,
    builder: (_) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SleepTimerTile(),
          OptionsMenu(song: song),
        ],
      ),
    ),
  );
}

// =============================================================================
// Bottom row — Lyrics · Devices · Queue
// =============================================================================

class _BottomRow extends ConsumerWidget {
  final _Pane pane;
  final ValueChanged<_Pane> onTogglePane;
  const _BottomRow({required this.pane, required this.onTogglePane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(playerProvider.select((s) => s.syncMode == SyncMode.passive));
    final sleeping = ref.watch(sleepTimerProvider.select((s) => s.active));
    Color c(bool on) => on ? Colors.white : Colors.white.withValues(alpha: 0.72);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GlyphButton(
          size: 48,
          semanticLabel: 'Lyrics',
          selected: pane == _Pane.lyrics,
          onTap: () => onTogglePane(_Pane.lyrics),
          child: Icon(Icons.format_quote_rounded, size: 24, color: c(pane == _Pane.lyrics)),
        ),
        GlyphButton(
          size: 48,
          semanticLabel: 'Devices',
          selected: remote,
          onTap: () => _showDevices(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.speaker_group_rounded, size: 24, color: c(remote)),
              if (sleeping)
                Positioned(
                  right: -5,
                  top: -3,
                  child: Icon(Icons.bedtime_rounded, size: 11, color: Colors.white.withValues(alpha: 0.9)),
                ),
            ],
          ),
        ),
        GlyphButton(
          size: 48,
          semanticLabel: 'Queue',
          selected: pane == _Pane.queue,
          onTap: () => onTogglePane(_Pane.queue),
          child: Icon(Icons.format_list_bulleted_rounded, size: 24, color: c(pane == _Pane.queue)),
        ),
      ],
    );
  }
}

void _showDevices(BuildContext context) {
  showPlatformSheet(context: context, title: 'Playing on', builder: (_) => const _DevicesSheet());
}

class _DevicesSheet extends ConsumerWidget {
  const _DevicesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final mode = ref.watch(playerProvider.select((s) => s.syncMode));
    final remoteName = ref.watch(playerProvider.select((s) => s.remoteActiveDeviceName));
    final here = mode != SyncMode.passive;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Playing on', style: naviText(20, FontWeight.w700, t.textPrimary)),
          ),
          ListTile(
            leading: Icon(
              PlatformUtils.isDesktop ? Icons.computer_rounded : Icons.smartphone_rounded,
              color: here ? t.accent : t.textSecondary,
            ),
            title: const Text('This device'),
            subtitle: Text(here ? 'Playing here' : 'Tap to move playback here'),
            trailing: here ? Icon(Icons.graphic_eq_rounded, color: t.accent) : null,
            onTap: here
                ? null
                : () {
                    ref.read(playerProvider.notifier).claimActiveDevice();
                    Navigator.pop(context);
                  },
          ),
          if (!here)
            ListTile(
              leading: Icon(Icons.devices_other_rounded, color: t.accent),
              title: Text(remoteName ?? 'Another device'),
              subtitle: const Text('Playing now'),
              trailing: Icon(Icons.graphic_eq_rounded, color: t.accent),
            ),
          if (here)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(
                'Other NaviVibe devices signed in to your account show up here while they play.',
                style: naviText(13, FontWeight.w400, t.textMuted).copyWith(height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown above the scrubber while another device holds playback.
class _RemoteDeviceBanner extends ConsumerWidget {
  const _RemoteDeviceBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passive = ref.watch(playerProvider.select((s) => s.syncMode == SyncMode.passive));
    final name = ref.watch(playerProvider.select((s) => s.remoteActiveDeviceName));
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: !passive
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speaker_group_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Playing on ${name ?? 'another device'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: naviText(13.5, FontWeight.w600, Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.read(playerProvider.notifier).claimActiveDevice(),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: Text('Play here', style: naviText(13.5, FontWeight.w700, Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// =============================================================================
// Wide layout (desktop window / tablet landscape)
// =============================================================================

class _WideLayout extends ConsumerStatefulWidget {
  final Song song;
  final bool playing;
  const _WideLayout({required this.song, required this.playing});

  @override
  ConsumerState<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends ConsumerState<_WideLayout> {
  _Pane _pane = _Pane.lyrics;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(playerProvider.notifier);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                GlassCircleButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  semanticLabel: 'Close player (Esc)',
                  onTap: () => Navigator.maybePop(context),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 40, 28),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: LayoutBuilder(builder: (context, c) {
                          // Cover takes what the controls below leave (they need ~330dp).
                          final art = math.max(160.0, math.min(c.maxWidth, c.maxHeight - 330));
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Cover(
                                song: widget.song,
                                size: art,
                                radius: 14,
                                scale: widget.playing ? 1 : 0.9,
                              ),
                              const SizedBox(height: 28),
                              _TitleRow(song: widget.song),
                              const SizedBox(height: 14),
                              Scrubber(player: notifier.player, song: widget.song),
                              const SizedBox(height: 4),
                              TransportControls(
                                playing: widget.playing,
                                onPlayPause: notifier.togglePlay,
                                onPrevious: notifier.playPrev,
                                onNext: notifier.playNext,
                                scale: 0.86,
                              ),
                              const SizedBox(height: 8),
                              VolumeBar(player: notifier.player),
                              const SizedBox(height: 12),
                              _BottomRow(
                                pane: _pane,
                                onTogglePane: (p) => setState(() => _pane = _pane == p ? _Pane.none : p),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 6,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: switch (_pane) {
                        _Pane.queue => const QueuePane(
                            key: ValueKey('wq'),
                            style: NowPlayingStyle.onArtwork,
                            showCurrent: true,
                          ),
                        _Pane.lyrics => const LyricsPane(
                            key: ValueKey('wl'),
                            style: NowPlayingStyle.onArtwork,
                            fontSize: 38,
                            padding: EdgeInsets.fromLTRB(8, 120, 8, 0),
                          ),
                        _Pane.none => const SizedBox.shrink(),
                      },
                    ),
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
