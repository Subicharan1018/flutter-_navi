import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../core/navigation_transitions.dart';
import '../core/theme.dart';
import '../core/palette_cache.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// Mini Player
// Deep glassmorphism shell: layered BackdropFilter blur, iridescent rim,
// frosted top-highlight streak, artwork-glow progress bar.
// The artwork-extracted themeColor drives: progress bar, play button,
// album glow, border rim, and outer shadow.
// =============================================================================

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  late Color _themeColor;
  String? _lastImageUrl;

  // ── Horizontal-swipe debounce guard ──────────────────────────────────────
  // Prevents rapid-fire next/prev calls if the user swipes multiple times
  // before the track has switched.
  bool _horizontalSwipeInProgress = false;
  Timer? _swipeDebounceTimer;

  @override
  void dispose() {
    _swipeDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeColor = ThemeTokens.of(context).accent;
  }

  void _openNowPlaying(String imageUrl) {
    if (PlatformUtils.prefersSidebarNavigation ||
        MediaQuery.of(context).size.width >= PlatformUtils.kDesktopBreakpoint) {
      return;
    }
    Navigator.of(context).push(
      AppRouteTransitions.slideUp(
        builder: (_) => NowPlayingScreen(initialImageUrl: imageUrl),
      ),
    );
  }

  Future<void> _loadPalette(String songId, String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

    final cached = PaletteCache.instance.getColorsFor(songId);
    if (cached != null && cached.length > 1) {
      if (mounted) {
        setState(() => _themeColor = cached[1]);
      }
      return;
    }

    try {
      final colors = await PaletteCache.instance.extractAndCache(songId, imageUrl);
      if (mounted && colors.length > 1) {
        setState(() => _themeColor = colors[1]);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _themeColor = ThemeTokens.of(context).accent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final service = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty) return SizedBox.shrink();

    final song = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);

    // Try to instantly read the vibrant color from cache to prevent flashing
    final cachedColors = PaletteCache.instance.peekColorsFor(song.id);
    final activeThemeColor = (cachedColors != null && cachedColors.length > 1)
        ? cachedColors[1]
        : _themeColor;

    // Defer palette load past the current frame to avoid cascading rebuilds.
    if (imageUrl != _lastImageUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPalette(song.id, imageUrl);
      });
    }

    return Semantics(
      label: 'Now playing: ${song.title} by ${song.artist}',
      child: GestureDetector(
        onTap: () => _openNowPlaying(imageUrl),
        // Existing: swipe up → open Now Playing
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -300) _openNowPlaying(imageUrl);
        },
        // New: swipe left → next track, swipe right → previous track
        onHorizontalDragEnd: (details) {
          if (_horizontalSwipeInProgress) return;
          final vx = details.primaryVelocity ?? 0;
          if (vx.abs() < 300) return; // ignore slow drags
          _horizontalSwipeInProgress = true;
          _swipeDebounceTimer?.cancel();
          HapticFeedback.lightImpact();
          final notifier = ref.read(playerProvider.notifier);
          () async {
            try {
              if (vx < 0) {
                await notifier.playNext(); // swipe left → forward
              } else {
                await notifier.playPrev(); // swipe right → backward
              }
            } catch (_) {
              // playNext/playPrev log internally; swallow here to ensure
              // the finally block always resets the guard.
            } finally {
              // Minimum cooldown even on fast returns, then unlock.
              // Guard against dispose: setState throws if widget is unmounted.
              await Future.delayed(const Duration(milliseconds: 300));
              if (mounted) setState(() => _horizontalSwipeInProgress = false);
            }
          }();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _GlassShell(
            themeColor: activeThemeColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Frosted top highlight streak ─────────────────────────────
                _TopHighlightStreak(),

                // ── Content row ──────────────────────────────────────────────
                SizedBox(
                  height: 68,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // AnimatedSwitcher keyed on song.id gives a quick cross-fade
                    // whenever the track changes (including via swipe gesture).
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      // Wrap outgoing children in IgnorePointer so taps on
                      // the fading-out row don't fire on the previous song.
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            ...previousChildren.map(
                              (c) => IgnorePointer(child: c),
                            ),
                            ?currentChild,
                          ],
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(
                          song.id,
                        ), // required for animation to fire
                        child: Row(
                          children: [
                            // Album art thumbnail
                            _AlbumThumb(
                              imageUrl: imageUrl,
                              themeColor: activeThemeColor,
                            ),
                            SizedBox(width: 12),

                            // Song info — constrained to avoid overflow
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeTokens.of(
                                        context,
                                      ).textPrimary,
                                      letterSpacing: -0.2,
                                      height: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: ThemeTokens.of(
                                        context,
                                      ).textSecondary,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(width: 4),

                            // Favourite — 48dp tap target
                            Semantics(
                              button: true,
                              label: playerState.starredIds.contains(song.id)
                                  ? 'Remove from favourites'
                                  : 'Add to favourites',
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    playerState.starredIds.contains(song.id)
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color:
                                        playerState.starredIds.contains(song.id)
                                        ? activeThemeColor
                                        : ThemeTokens.of(context).textMuted,
                                    size: 20,
                                  ),
                                  onPressed: () => ref
                                      .read(playerProvider.notifier)
                                      .toggleStar(song.id),
                                ),
                              ),
                            ),

                            // Play / Pause pill
                            _PlayButton(
                              isPlaying: playerState.isPlaying,
                              themeColor: activeThemeColor,
                              onPressed: () {
                                final n = ref.read(playerProvider.notifier);
                                if (playerState.isPlaying) {
                                  n.player.pause();
                                } else {
                                  n.player.play();
                                }
                              },
                            ),

                            // Skip — 48dp tap target
                            Semantics(
                              button: true,
                              label: 'Skip to next track',
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: ThemeTokens.of(
                                      context,
                                    ).textSecondary,
                                    size: 24,
                                  ),
                                  onPressed: () => ref
                                      .read(playerProvider.notifier)
                                      .playNext(),
                                ),
                              ),
                            ),
                          ],
                        ), // Row
                      ), // KeyedSubtree
                    ), // AnimatedSwitcher
                  ),
                ),

                // ── Progress bar ─────────────────────────────────────────────
                // Own StatefulWidget — 60fps rebuilds scoped to 3px paint only.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: _MiniProgressBar(
                    player: ref.read(playerProvider.notifier).player,
                    durationSeconds: song.duration,
                    themeColor: activeThemeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Frosted top highlight streak
// Simulates real glass catching overhead light — a horizontal shimmer
// across the very top edge of the pill.
// =============================================================================

class _TopHighlightStreak extends StatelessWidget {
  const _TopHighlightStreak();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              Color(0x55FFFFFF), // ~33% white
              Color(0x88FFFFFF), // ~53% white — brightest point
              Color(0x55FFFFFF),
              Colors.transparent,
            ],
            stops: [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
        ),
      ),
    );
  }
}

class _GlassShell extends StatelessWidget {
  final Widget child;
  final Color themeColor;
  const _GlassShell({required this.child, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    final darkBase = Color.lerp(themeColor, const Color(0xFF1E2628), 0.75)!;
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: darkBase.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: _NoiseLayer(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Noise grain layer
// Paints a subtle film-grain texture over the glass surface using a
// CustomPainter so no asset files are required.
// =============================================================================

class _NoiseLayer extends StatelessWidget {
  final Widget child;
  const _NoiseLayer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _NoisePainter())),
        ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  static final Paint _noisePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.018)
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 4.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final h =
            ((x * 374761393 + y * 668265263).truncate() ^ 0x9e3779b9) & 0xFFFF;
        if (h > 0xC000) {
          canvas.drawCircle(Offset(x, y), 0.5, _noisePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NoisePainter old) => false;
}

// =============================================================================
// Album thumbnail
// =============================================================================

class _AlbumThumb extends StatelessWidget {
  final String imageUrl;
  final Color themeColor;
  const _AlbumThumb({required this.imageUrl, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    final imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 42,
        height: 42,
        memCacheWidth: 84,
        memCacheHeight: 84,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: ThemeTokens.of(context).bgElevated,
          child: Icon(
            Icons.music_note_rounded,
            color: ThemeTokens.of(context).textMuted,
            size: 20,
          ),
        ),
      ),
    );

    // On Mobile: Hero transition smoothly animates artwork between MiniPlayer and NowPlayingScreen.
    // On Desktop: Direct rendering to avoid duplicate Hero tag crashes between side-panel and player bar.
    if (PlatformUtils.isDesktop) {
      return SizedBox(width: 42, height: 42, child: imageWidget);
    }

    return SizedBox(
      width: 42,
      height: 42,
      child: Hero(
        tag: 'nowplaying_art_$imageUrl',
        child: imageWidget,
      ),
    );
  }
}

// =============================================================================
// Play / Pause button
// Four-layer lighting model for a convincing glass pill:
//   1. Base gradient (theme → darker theme)
//   2. Outer artwork-coloured glow shadow
//   3. Top-edge inset highlight (simulates light hitting button top)
//   4. Bottom-edge inset shadow (simulates depth underside)
// =============================================================================

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final Color themeColor;
  final VoidCallback onPressed;

  const _PlayButton({
    required this.isPlaying,
    required this.themeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isPlaying ? 'Pause' : 'Play',
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 28,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

// =============================================================================
// Progress bar — isolated StatefulWidget (60 fps scope)
// =============================================================================

class _MiniProgressBar extends StatefulWidget {
  final AudioPlayer player;
  final int durationSeconds;
  final Color themeColor;

  const _MiniProgressBar({
    required this.player,
    required this.durationSeconds,
    required this.themeColor,
  });

  @override
  State<_MiniProgressBar> createState() => _MiniProgressBarState();
}

class _MiniProgressBarState extends State<_MiniProgressBar> {
  StreamSubscription<Duration>? _sub;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.positionStream.listen(_onPosition);
  }

  void _onPosition(Duration position) {
    final totalMs = widget.durationSeconds * 1000;
    if (totalMs <= 0 || !mounted) return;
    final p = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    if ((p - _progress).abs() > 0.001) {
      setState(() => _progress = p);
    }
  }

  @override
  void didUpdateWidget(_MiniProgressBar old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _sub?.cancel();
      _sub = widget.player.positionStream.listen(_onPosition);
    }
    if (old.durationSeconds != widget.durationSeconds) {
      setState(() => _progress = 0.0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: CustomPaint(
        painter: _ProgressPainter(_progress, widget.themeColor),
        size: const Size(double.infinity, 3),
      ),
    );
  }
}

// =============================================================================
// Progress painter
// Three-layer rendering:
//   1. Track — faint white capsule
//   2. Glow bloom — blurred artwork-coloured halo behind the fill
//   3. Filled bar — gradient from semi-transparent to full theme colour
//   4. Leading-edge dot — bright thumb at playhead position
// =============================================================================

class _ProgressPainter extends CustomPainter {
  final double progress;
  final Color themeColor;
  const _ProgressPainter(this.progress, this.themeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = h / 2;
    final fill = (w * progress).clamp(0.0, w);

    // 1. Inactive Track — translucent white
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );

    if (fill <= 0) return;

    // 2. Active Progress Line — solid crisp white
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fill, h), Radius.circular(r)),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.themeColor != themeColor;
}
