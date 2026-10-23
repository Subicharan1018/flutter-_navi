import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';

import '../core/theme.dart';
import '../models/composer.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/artwork_field.dart';
import '../player/lyrics_pane.dart';
import '../player/now_playing_style.dart';
import '../player/mode_buttons.dart';
import '../player/player_controls.dart';
import '../player/queue_pane.dart';
import '../player/sleep_timer.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/platform_utils.dart';
import '../widgets/desktop_dialogs.dart';
import '../widgets/options_menu.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/ion.dart';

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
  /// 0 = player, 1 = Lyrics/Queue open; driven by springs (see [_flyTo]).
  late final AnimationController _paneAnim = AnimationController(vsync: this);

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
        _flyTo(0);
      } else {
        _pane = p;
        _shownPane = p;
        _flyTo(1);
      }
    });
  }

  void _closePane() {
    if (_pane == _Pane.none) return;
    setState(() => _pane = _Pane.none);
    _flyTo(0);
  }

  /// The cover-to-header flight runs on a spring that starts from the
  /// flight's current velocity, so tapping Lyrics again mid-flight turns the
  /// motion around smoothly instead of restarting a curve from rest.
  void _flyTo(double target) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _paneAnim.value = target;
      return;
    }
    _paneAnim.animateWith(SpringSimulation(Motion.flight, _paneAnim.value, target, _paneAnim.velocity));
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
                      lit: playing,
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
    // The covers either side of this one, for the swipe carousel.
    final index = ref.watch(playerProvider.select((s) => s.currentIndex));
    final previous = ref.watch(playerProvider.select((s) => index > 0 && index - 1 < s.queue.length ? s.queue[index - 1] : null));
    final next = ref.watch(playerProvider.select((s) => index + 1 < s.queue.length ? s.queue[index + 1] : null));

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
            previous: previous,
            next: next,
            onNext: notifier.playNext,
            // The swipe shows the queue's previous cover, so it plays exactly
            // that song (the ⏮ button keeps "restart, then previous").
            onPrevious: () => notifier.jumpTo(index - 1),
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
                // Apple Music's three: shuffle and repeat live in the queue.
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

  /// Neighbouring songs in the queue, shown as the carousel's side covers.
  final Song? previous;
  final Song? next;
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
    required this.previous,
    required this.next,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  static const double _headerArt = 60;
  static const double _headerTop = 6;
  static const double _titleH = 80; // title + composer + artist
  static const double _titleGap = 26;

  /// Space between covers in the carousel.
  static const double _coverGap = 28;

  /// Pull past a missing neighbour: Apple's asymptotic resistance, never
  /// travelling further than this fraction of a stride however far you drag.
  static const double _rubberBandReach = 0.35;

  /// A flick at least this fast decides the direction on its own.
  static const double _flingVelocity = 700;

  /// How long a committed swipe waits for the song to change before giving
  /// up and coming home (end of queue, a failed load).
  static const Duration _commitTimeout = Duration(seconds: 4);

  static final SpringDescription _spring = Motion.deck;

  /// How far the cover recedes while paused.
  static const double _pausedScale = 0.84;

  // The carousel: the cover follows the finger 1:1 with the next and previous
  // covers riding alongside. Past the threshold it carries on to the
  // neighbour, which then becomes the song; otherwise it springs home.
  late final AnimationController _swipe = AnimationController.unbounded(vsync: this);

  /// True between a committed swipe and the song actually changing; the
  /// cover then swaps without a cross-fade, since the neighbour already
  /// slid into place showing the new art.
  bool _committed = false;

  /// Where a committed swipe is heading (± one stride).
  double _commitTarget = 0;
  Timer? _settle;

  /// The finger's own travel this drag; [_swipe] shows it, resisted where
  /// there's no neighbour to reveal.
  double _finger = 0;

  /// Cover width plus gap, from the last layout.
  double _stride = 1;

  /// True while a song change made elsewhere (skip buttons, the
  /// notification, the song ending) glides the covers across, so the cover
  /// swaps without its cross-fade.
  bool _gliding = false;

  @override
  void didUpdateWidget(_Stage old) {
    super.didUpdateWidget(old);
    if (old.song.id == widget.song.id) return;
    if (_committed) {
      // The neighbour has become the song. Rebase the offset so the new
      // centre cover continues from exactly where the neighbour was, and
      // finish the glide home with the velocity it already had.
      _settle?.cancel();
      final velocity = _swipe.velocity;
      _swipe.value = _swipe.value - _commitTarget;
      _swipe.animateWith(SpringSimulation(_spring, _swipe.value, 0, velocity));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _committed = false);
      });
      return;
    }
    // Same spatial model as the swipe for every other change: when the old
    // song is now a neighbour, the new cover arrives from that side. A jump
    // to an unrelated song keeps the cross-fade.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final forward = widget.previous?.id == old.song.id;
    final back = widget.next?.id == old.song.id;
    if (reduce || widget.pane != _Pane.none || !(forward || back)) return;
    _gliding = true;
    _swipe.value = forward ? _stride : -_stride;
    _swipe.animateWith(SpringSimulation(_spring, _swipe.value, 0, 0)).whenCompleteOrCancel(() {
      if (mounted && _gliding) setState(() => _gliding = false);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _swipe.dispose();
    super.dispose();
  }

  void _swipeStart(DragStartDetails _) {
    if (_committed) return;
    // Catching a glide mid-flight hands it to the finger.
    _swipe.stop();
    _gliding = false;
    _finger = _swipe.value;
  }

  void _swipeUpdate(DragUpdateDetails d) {
    if (_committed) return;
    _finger += d.delta.dx;
    final missing = (_finger < 0 && widget.next == null) || (_finger > 0 && widget.previous == null);
    _swipe.value = missing ? _resist(_finger) : _finger;
  }

  /// x·s/(|x|+s): follows the finger at first, then stiffens toward a limit.
  double _resist(double x) {
    final limit = _stride * _rubberBandReach;
    return x * limit / (x.abs() + limit);
  }

  void _home([double velocity = 0]) =>
      _swipe.animateWith(SpringSimulation(_spring, _swipe.value, 0, velocity));

  void _swipeEnd(DragEndDetails d) {
    if (_committed) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _swipe.value;
    // A real flick decides by its own direction; otherwise where it was let go.
    final flick = v.abs() > _flingVelocity;
    final forward = flick ? v < 0 : dx < 0;
    final neighbour = forward ? widget.next : widget.previous;
    // A flick back against the drag means "never mind".
    final opposes = flick && dx != 0 && (v < 0) != (dx < 0);
    final go = neighbour != null && !opposes && (flick || dx.abs() > _stride * 0.28);
    if (!go) {
      _home(v);
      return;
    }
    HapticFeedback.lightImpact();
    final target = forward ? -_stride : _stride;
    setState(() {
      _committed = true;
      _commitTarget = target;
    });
    _swipe.animateWith(SpringSimulation(_spring, dx, target, v));
    forward ? widget.onNext() : widget.onPrevious();
    // If playback refuses the change (end of queue, an error), come home.
    _settle = Timer(_commitTimeout, () {
      if (!mounted || !_committed) return;
      setState(() => _committed = false);
      _home();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // Apple's arrangement: the title sits right above the scrubber, and
        // the cover takes the space above it, a little above centre.
        final titleTop0 = h - _titleH - 6;
        final room = titleTop0 - _titleGap;
        final artSize = math.min(w - 56, room - 8).clamp(140.0, 520.0);
        final top0 = math.max(4.0, (room - artSize) * 0.42);
        final big = Rect.fromLTWH((w - artSize) / 2, top0, artSize, artSize);
        const small = Rect.fromLTWH(20, _headerTop, _headerArt, _headerArt);
        final stride = artSize + _coverGap;
        _stride = stride;

        // Built once per stage build and only positioned on each animation
        // frame: the same widget instances let Flutter skip rebuilding them
        // while the covers swipe or the pane flies (the title measures
        // itself for the marquee, and the queue is a whole list).
        final title = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey(widget.song.id),
            child: _TitleRow(song: widget.song),
          ),
        );
        final pane = AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: widget.shownPane == _Pane.queue
              ? const QueuePane(key: ValueKey('queue'), style: NowPlayingStyle.onArtwork)
              : const LyricsPane(key: ValueKey('lyrics'), style: NowPlayingStyle.onArtwork),
        );

        return AnimatedBuilder(
          animation: Listenable.merge([widget.paneAnim, _swipe]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(widget.paneAnim.value);
            final artRect = Rect.lerp(big, small, t)!;
            final titleLeft = _lerp(28, small.right + 14, t);
            final titleTop = _lerp(titleTop0, _headerTop + 4, t);
            final titleScale = _lerp(1, 0.8, t);
            final paneTop = small.bottom + 12;
            final paneT = Curves.easeOutCubic.transform(((widget.paneAnim.value - 0.25) / 0.75).clamp(0.0, 1.0));
            final inPlayer = widget.pane == _Pane.none && widget.paneAnim.value == 0;
            final dx = _swipe.value * (1 - t);
            // Covers shrink a touch as they leave the centre, like a deck.
            double depth(double offset) => 1 - 0.08 * (offset.abs() / stride).clamp(0.0, 1.0);
            // Apple's signature: the cover recedes while paused. The centre
            // cover reaches it on a spring; side covers (seen only mid-swipe)
            // simply match the resting size.
            final restScale = reduce || widget.playing ? 1.0 : _pausedScale;
            final pausedScale = _lerp(restScale, 1, t);
            // Null when there's nothing to show: a non-positioned placeholder
            // would collapse the Stack's width and shift the whole stage. A
            // neighbour wholly off screen is skipped too, so it isn't decoded
            // and painted for nothing.
            Widget? side(Song? s, double offset) {
              final rect = artRect.shift(Offset(offset, 0));
              if (s == null || dx.abs() < 0.5 || rect.right <= 0 || rect.left >= w) return null;
              return Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: depth(offset) * pausedScale,
                    child: _SideCover(song: s, size: artRect.width, radius: 12),
                  ),
                ),
              );
            }

            return Stack(
              fit: StackFit.expand,
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
                        child: pane,
                      ),
                    ),
                  ),

                // Background drag target in player mode (dismiss gesture).
                if (inPlayer) Positioned.fill(child: widget.dismissible(const SizedBox.expand())),

                // Carousel neighbours.
                ?side(widget.previous, dx - stride),
                ?side(widget.next, dx + stride),

                // Cover.
                Positioned.fromRect(
                  rect: artRect.shift(Offset(dx, 0)),
                  child: GestureDetector(
                    onTap: widget.pane != _Pane.none ? widget.onClosePane : null,
                    onHorizontalDragStart: inPlayer ? _swipeStart : null,
                    onHorizontalDragUpdate: inPlayer ? _swipeUpdate : null,
                    onHorizontalDragEnd: inPlayer ? _swipeEnd : null,
                    onHorizontalDragCancel: inPlayer
                        ? () {
                            if (!_committed) _home();
                          }
                        : null,
                    child: widget.dismissible(
                      Transform.scale(
                        scale: depth(dx),
                        child: _Cover(
                          song: widget.song,
                          size: artRect.width,
                          radius: _lerp(12, 7, t),
                          scale: restScale,
                          flatten: t,
                          instantSwap: _committed || _gliding,
                        ),
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
                    child: title,
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

  /// Resting scale: 1 while playing, smaller while paused. Reached on a
  /// spring (see [_SpringScale]).
  final double scale;

  /// 0..1: how far the cover has flown into the pane header, where it sits
  /// at full size whatever the play state.
  final double flatten;

  /// Swap art without the cross-fade (the carousel already slid it in).
  final bool instantSwap;

  const _Cover({
    required this.song,
    required this.size,
    required this.radius,
    required this.scale,
    this.flatten = 0,
    this.instantSwap = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final deep = ref.watch(albumPaletteProvider).deep;
    return _SpringScale(
      target: scale,
      flatten: flatten,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [_coverShadow(deep, size)],
        ),
        child: Hero(
          tag: 'np_cover',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedSwitcher(
              duration: instantSwap ? Duration.zero : const Duration(milliseconds: 320),
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
    );
  }
}

/// Scales its child to [target] on Apple's spring ([Motion.cover]). A new
/// target mid-flight (pause → play → pause in quick taps) carries the
/// current velocity into the next spring, so the cover never jerks; the
/// growth lands with a slight bounce, as Apple Music's cover does when music
/// starts. [flatten] blends the result toward 1 for the pane header.
class _SpringScale extends StatefulWidget {
  final double target;
  final double flatten;
  final Widget child;
  const _SpringScale({required this.target, required this.flatten, required this.child});

  @override
  State<_SpringScale> createState() => _SpringScaleState();
}

class _SpringScaleState extends State<_SpringScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: widget.target);

  @override
  void didUpdateWidget(_SpringScale old) {
    super.didUpdateWidget(old);
    if (widget.target == old.target) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _scale.value = widget.target;
    } else {
      _scale.animateWith(SpringSimulation(Motion.cover, _scale.value, widget.target, _scale.velocity));
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value + (1 - _scale.value) * widget.flatten,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A neighbouring cover in the swipe carousel. Same art, same shadow; the
/// image decode is shared with the real cover through the cache key.
class _SideCover extends ConsumerWidget {
  final Song song;
  final double size;
  final double radius;
  const _SideCover({required this.song, required this.size, required this.radius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final deep = ref.watch(albumPaletteProvider.select((p) => p.deep));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [_coverShadow(deep, size)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: size, height: size, cacheWidth: 1000),
      ),
    );
  }
}

/// The cover's lift off the artwork field: offset and soft, in the album's
/// own darkest tone.
BoxShadow _coverShadow(Color deep, double size) => BoxShadow(
      color: Color.lerp(deep, Colors.black, 0.4)!.withValues(alpha: 0.55),
      blurRadius: size * 0.12,
      offset: Offset(0, size * 0.05),
    );

// =============================================================================
// Title row — title, artist, favourite, more
// =============================================================================

class _TitleRow extends ConsumerWidget {
  final Song song;
  const _TitleRow({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final titleStyle = naviText(22, FontWeight.w700, Colors.white);
    final composer = composerLineFor(song);
    // The composer leads; singers sit quieter beneath it.
    final composerStyle = naviText(18, FontWeight.w500, Colors.white.withValues(alpha: 0.82));
    final artistStyle = composer == null
        ? naviText(19, FontWeight.w500, Colors.white.withValues(alpha: 0.68))
        : naviText(15, FontWeight.w400, Colors.white.withValues(alpha: 0.58));
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
              if (composer != null)
                Text(composer, maxLines: 1, overflow: TextOverflow.ellipsis, style: composerStyle),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: artistStyle),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GlassCircleButton(
          ion: starred ? Ion.star : Ion.starOutline,
          semanticLabel: starred ? 'Remove from favourites' : 'Add to favourites',
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(playerProvider.notifier).toggleStar(song.id);
          },
        ),
        GlassCircleButton(
          ion: Ion.ellipsis,
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
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SleepTimerTile(),
        OptionsMenu(song: song),
      ],
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
          child: IonIcon(Ion.lyrics, size: 24, color: c(pane == _Pane.lyrics)),
        ),
        GlyphButton(
          size: 48,
          semanticLabel: 'Devices',
          selected: remote,
          onTap: () => _showDevices(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IonIcon(Ion.devices, size: 24, color: c(remote)),
              if (sleeping)
                const Positioned(
                  right: -5,
                  top: -3,
                  child: IonIcon(Ion.moon, size: 11, color: Colors.white),
                ),
            ],
          ),
        ),
        GlyphButton(
          size: 48,
          semanticLabel: 'Queue',
          selected: pane == _Pane.queue,
          onTap: () => onTogglePane(_Pane.queue),
          child: IonIcon(Ion.queue, size: 24, color: c(pane == _Pane.queue)),
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
    final playingGlyph = Icon(CupertinoIcons.waveform, size: 20, color: t.accent);
    final player = ref.read(playerProvider.notifier);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetGroup(children: [
            SheetAction(
              label: PlatformUtils.isDesktop ? 'This Computer' : 'This Phone',
              detail: here ? 'Playing here' : 'Tap to move playback here',
              trailing: here ? playingGlyph : null,
              onTap: here ? null : player.claimActiveDevice,
            ),
            if (!here)
              SheetAction(
                label: remoteName ?? 'Another device',
                detail: 'Playing now',
                trailing: playingGlyph,
              ),
          ]),
          if (here)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
              child: Text(
                'Other NaviVibe devices signed in to your account show up here while they play.',
                style: t.footnote,
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
                    const Icon(CupertinoIcons.hifispeaker, size: 18, color: Colors.white),
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
                  icon: CupertinoIcons.chevron_down,
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
                          // Cover takes what the controls below leave (they need ~356dp with the composer line).
                          final art = math.max(160.0, math.min(c.maxWidth, c.maxHeight - 356));
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
                                leading: const ShuffleModeButton(scale: 0.9),
                                trailing: const RepeatModeButton(scale: 0.9),
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
