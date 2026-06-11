import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../core/navigation_transitions.dart';
import '../core/theme.dart';
import '../utils/platform_utils.dart';

// ---------------------------------------------------------------------------
// Isolate-safe colour extraction — runs on main isolate (required by Flutter)
// ---------------------------------------------------------------------------
Future<Color?> _extractMiniPalette(
  String imageUrl,
  BuildContext context,
) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl),
      size: const Size(40, 40),
      maximumColorCount: 5,
    );
    return palette.vibrantColor?.color ??
        palette.dominantColor?.color ??
        ThemeTokens.of(context).accent;
  } catch (_) {
    return ThemeTokens.of(context).accent;
  }
}

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
    // On desktop: use rootNavigator so NowPlayingScreen covers the full
    // window (including the sidebar), not just the content column.
    Navigator.of(context, rootNavigator: PlatformUtils.isDesktop).push(
      AppRouteTransitions.slideUp(
        builder: (_) => NowPlayingScreen(initialImageUrl: imageUrl),
      ),
    );
  }

  Future<void> _loadPalette(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;
    final color = await _extractMiniPalette(imageUrl, context);
    if (mounted && color != null) {
      setState(() => _themeColor = color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final service = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty) return SizedBox.shrink();

    final song = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);

    // Defer palette load past the current frame to avoid cascading rebuilds.
    if (imageUrl != _lastImageUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPalette(imageUrl);
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
            themeColor: _themeColor,
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
                            if (currentChild != null) currentChild,
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
                              themeColor: _themeColor,
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
                                        ? _themeColor
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
                              themeColor: _themeColor,
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
                    themeColor: _themeColor,
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

// =============================================================================
// Glassmorphism shell
// Layers (back → front):
//   1. Outer coloured glow + depth shadow (BoxDecoration on wrapper Container)
//   2. ClipRRect + BackdropFilter blur (sigmaX/Y 26, saturate 160%)
//   3. Directional glass gradient overlay (top-left light → bottom-right dark)
//   4. Iridescent rim — theme-coloured border with a subtle shimmer gradient
//   5. Top highlight streak (rendered by child Column)
//   6. Noise texture layer (very low opacity SVG-style grain via ShaderMask)
// =============================================================================

class _GlassShell extends StatelessWidget {
  final Widget child;
  final Color themeColor;
  const _GlassShell({required this.child, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          // Wide soft artwork-coloured outer glow
          BoxShadow(
            color: themeColor.withValues(alpha: 0.22),
            blurRadius: 36,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
          // Tighter, more saturated inner glow ring
          BoxShadow(
            color: themeColor.withValues(alpha: 0.12),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          // Dark depth shadow underneath
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              // Directional gradient overlay: brighter top-left, darker bottom-right
              // simulates glass catching angled overhead light.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.22),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
              // Iridescent rim: theme colour at low opacity, thicker than before
              border: Border.all(
                color: themeColor.withValues(alpha: 0.28),
                width: 1.0,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            // Stack noise grain over the glass body at near-zero opacity
            child: _NoiseLayer(child: child),
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
        // Grain overlay — CustomPaint with a very low-opacity random noise pass.
        // Positioned fill so it never affects layout.
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _NoisePainter())),
        ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Lightweight deterministic "noise" — draw a sparse grid of micro-dots.
    // Full random noise would require dart:math import and is more expensive;
    // this approach is zero-allocation and visually sufficient.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;

    const step = 4.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        // Pseudo-random dot placement using a cheap bit-mix hash
        final h =
            ((x * 374761393 + y * 668265263).truncate() ^ 0x9e3779b9) & 0xFFFF;
        if (h > 0xC000) {
          canvas.drawCircle(Offset(x, y), 0.5, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NoisePainter old) => false; // static texture
}

// =============================================================================
// Album thumbnail
// Three-layer glow system:
//   1. Wide diffuse ambient glow (large blur, low opacity)
//   2. Tighter specular glow (small blur, higher opacity)
//   3. White inner edge border on the artwork itself
// =============================================================================

class _AlbumThumb extends StatelessWidget {
  final String imageUrl;
  final Color themeColor;
  const _AlbumThumb({required this.imageUrl, required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          // Wide ambient glow
          BoxShadow(
            color: themeColor.withValues(alpha: 0.30),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          // Tight specular glow — brighter, closer
          BoxShadow(
            color: themeColor.withValues(alpha: 0.45),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Hero(
        tag: 'now_playing_artwork',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            // White inner border to separate art from glass surface
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 0.8,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9.2),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: ThemeTokens.of(context).bgElevated,
                child: Icon(
                  Icons.music_note_rounded,
                  color: ThemeTokens.of(context).textMuted,
                  size: 20,
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
    // Compute a slightly darkened variant for the gradient bottom stop
    final darkened = Color.fromARGB(
      255,
      ((themeColor.r * 255.0) * 0.65).round().clamp(0, 255),
      ((themeColor.g * 255.0) * 0.65).round().clamp(0, 255),
      ((themeColor.b * 255.0) * 0.65).round().clamp(0, 255),
    );

    return Semantics(
      button: true,
      label: isPlaying ? 'Pause' : 'Play',
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 42,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [themeColor, darkened],
            ),
            boxShadow: [
              // Outer artwork glow
              BoxShadow(
                color: themeColor.withValues(alpha: 0.50),
                blurRadius: 18,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
              // Crisp depth shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 8,
                spreadRadius: -1,
                offset: const Offset(0, 3),
              ),
              // Top-edge inset highlight — white shimmer along the upper rim
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.22),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Subtle inner top-left sheen painted via a partial gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5],
                    ),
                  ),
                ),
              ),
              Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: ThemeTokens.of(context).textPrimary,
                size: 24,
              ),
            ],
          ),
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

    // 1. Track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    if (fill <= 0) return;

    // 2. Wide glow bloom behind the bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-3, -6, fill + 6, h + 12),
        const Radius.circular(8),
      ),
      Paint()
        ..color = themeColor.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // 3. Narrow inner glow (tighter, brighter)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1, -2, fill + 2, h + 4),
        const Radius.circular(4),
      ),
      Paint()
        ..color = themeColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 4. Filled bar — gradient: translucent → full colour
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fill, h), Radius.circular(r)),
      Paint()
        ..shader = LinearGradient(
          colors: [themeColor.withValues(alpha: 0.70), themeColor],
        ).createShader(Rect.fromLTWH(0, 0, fill, h)),
    );

    // 5. Leading-edge playhead dot — glowing thumb at progress position
    final thumbX = fill.clamp(r, w - r);
    // Outer glow ring of the thumb
    canvas.drawCircle(
      Offset(thumbX, h / 2),
      5.5,
      Paint()
        ..color = themeColor.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Playhead dot — uses white for strong contrast on the coloured track
    // (intentional: this is a specular highlight on the fill bar, not text)
    canvas.drawCircle(
      Offset(thumbX, h / 2),
      3.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.themeColor != themeColor;
}
