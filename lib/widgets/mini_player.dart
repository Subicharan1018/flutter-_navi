import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../core/navigation_transitions.dart';
import '../core/theme.dart';

// ---------------------------------------------------------------------------
// Isolate-safe colour extraction — runs on main isolate (required by Flutter)
// ---------------------------------------------------------------------------
Future<Color?> _extractMiniPalette(String imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      NetworkImage(imageUrl),
      size: const Size(40, 40),
      maximumColorCount: 5,
    );
    return palette.vibrantColor?.color ??
           palette.dominantColor?.color ??
           AppTheme.spotifyGreen;
  } catch (_) {
    return AppTheme.spotifyGreen;
  }
}

// =============================================================================
// Mini Player
// Glassmorphism shell with full BackdropFilter blur.
// The artwork-extracted themeColor drives: progress bar, play button, glow.
// =============================================================================

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  Color _themeColor = AppTheme.spotifyGreen;
  String? _lastImageUrl;

  void _openNowPlaying(String imageUrl) {
    Navigator.of(context).push(
      AppRouteTransitions.slideUp(
        builder: (_) => NowPlayingScreen(initialImageUrl: imageUrl),
      ),
    );
  }

  Future<void> _loadPalette(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;
    final color = await _extractMiniPalette(imageUrl);
    if (mounted && color != null) {
      setState(() => _themeColor = color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final service     = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty) return const SizedBox.shrink();

    final song     = playerState.queue[playerState.currentIndex];
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
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -300) _openNowPlaying(imageUrl);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _GlassShell(
            themeColor: _themeColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Content row ──────────────────────────────────────────────
                SizedBox(
                  height: 68,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        // Album art thumbnail
                        _AlbumThumb(imageUrl: imageUrl, themeColor: _themeColor),
                        const SizedBox(width: 12),

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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.2,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 4),

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
                                color: playerState.starredIds.contains(song.id)
                                    ? _themeColor
                                    : Colors.white38,
                                size: 20,
                              ),
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).toggleStar(song.id),
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
                              icon: const Icon(Icons.skip_next_rounded,
                                  color: Colors.white70, size: 24),
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).playNext(),
                            ),
                          ),
                        ),
                      ],
                    ),
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
// Glassmorphism shell
// Real BackdropFilter blur + translucent dark surface + coloured rim.
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
          // Artwork-coloured outer glow
          BoxShadow(
            color: themeColor.withOpacity(0.18),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          // Dark depth shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              // Translucent dark glass — shows blurred content beneath
              color: AppTheme.glassBackground,
              border: Border.all(
                color: themeColor.withOpacity(0.20),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Album thumbnail with artwork-coloured glow ring
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
          BoxShadow(
            color: themeColor.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Hero(
        tag: 'now_playing_artwork',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: 46,
            height: 46,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: AppTheme.topLevel,
              child: const Icon(Icons.music_note_rounded,
                  color: Colors.white24, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Play / Pause button with green gradient + artwork glow
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
              colors: [themeColor, themeColor.withOpacity(0.75)],
            ),
            boxShadow: [
              BoxShadow(
                color: themeColor.withOpacity(0.45),
                blurRadius: 16,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
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

// Simple progress painter — uses artwork themeColor.
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

    // Track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      Paint()..color = Colors.white.withOpacity(0.12),
    );

    if (fill <= 0) return;

    // Glow bloom
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-2, -4, fill + 4, h + 8), const Radius.circular(6)),
      Paint()
        ..color = themeColor.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Filled bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fill, h), Radius.circular(r)),
      Paint()
        ..shader = LinearGradient(
          colors: [themeColor.withOpacity(0.85), themeColor],
        ).createShader(Rect.fromLTWH(0, 0, fill, h)),
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.themeColor != themeColor;
}
