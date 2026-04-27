import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../core/navigation_transitions.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
class _G {
  // Glass surfaces
  static const glassBorder  = Color(0x28FFFFFF);
  static const glassShadow  = Color(0x55000000);

  // Neon progress
  static const neonA = Color(0xFF9D4EDD); // purple

  // Text
  static const titleColor  = Color(0xFFF5F5F7);
  static const artistColor = Color(0x99F5F5F7);
}

// ── Neon progress painter ─────────────────────────────────────────────────────
class _NeonProgressPainter extends CustomPainter {
  final double progress;
  final Color themeColor;
  const _NeonProgressPainter(this.progress, this.themeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = h / 2;
    final fill = (w * progress).clamp(0.0, w);

    // Inactive track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      Paint()..color = Colors.white.withOpacity(0.10),
    );

    if (fill <= 0) return;

    // Glow bloom behind
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-2, -5, fill + 4, h + 10),
        const Radius.circular(8),
      ),
      Paint()
        ..shader = LinearGradient(colors: [
          themeColor.withOpacity(0.45),
          themeColor.withOpacity(0.25),
        ]).createShader(Rect.fromLTWH(0, 0, fill, h))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Solid gradient fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fill, h), Radius.circular(r)),
      Paint()
        ..shader = LinearGradient(
          colors: [themeColor.withOpacity(0.8), themeColor, themeColor.withOpacity(0.9)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, 400, h)),
    );

    // Leading flare dot
    if (fill > r * 2) {
      canvas.drawCircle(
        Offset(fill - r, r),
        r * 0.55,
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(_NeonProgressPainter old) => old.progress != progress || old.themeColor != themeColor;
}

// ── Mini player ───────────────────────────────────────────────────────────────
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  Color? _artworkColor;
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

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(imageUrl),
        size: const Size(40, 40),
        maximumColorCount: 5,
      );
      if (mounted) {
        setState(() {
          _artworkColor = palette.vibrantColor?.color ??
                         palette.dominantColor?.color ??
                         const Color(0xFF1DB954);
        });
      }
    } catch (e) {
      debugPrint('MiniPlayer palette error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── All logic untouched ───────────────────────────────────────────────
    final playerState = ref.watch(playerProvider);
    final service     = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty) return const SizedBox.shrink();

    final song     = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);

    // BUG FIX: Only trigger palette load if the image URL actually changed.
    // Store _lastImageUrl BEFORE calling _loadPalette to avoid infinite loops.
    if (imageUrl != _lastImageUrl) {
      _lastImageUrl = imageUrl;
      _loadPalette(imageUrl);
    }

    final themeColor = _artworkColor ?? const Color(0xFF1DB954);

    return GestureDetector(
      onTap: () {
        _openNowPlaying(imageUrl);
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
          _openNowPlaying(imageUrl);
        }
      },

      // ── Visual shell ─────────────────────────────────────────────────────
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _GlassShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Content row ─────────────────────────────────────────────
              SizedBox(
                height: 68,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Album art with glow ring
                      _AlbumThumb(imageUrl: imageUrl),
                      const SizedBox(width: 12),

                      // Song info
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
                                color: _G.titleColor,
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
                                color: _G.artistColor,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Like
                      _MiniIconButton(
                        icon: playerState.starredIds.contains(song.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: playerState.starredIds.contains(song.id)
                            ? themeColor
                            : Colors.white38,
                        size: 20,
                        onPressed: () =>
                            ref.read(playerProvider.notifier).toggleStar(song.id),
                      ),

                      // Play / Pause — glowing pill button
                      _PlayButton(
                        isPlaying: playerState.isPlaying,
                        themeColor: themeColor,
                        onPressed: () {
                          final n = ref.read(playerProvider.notifier);
                          if (playerState.isPlaying) {
                            n.player.pause();
                          } else {
                            n.player.play();
                          }
                        },
                      ),

                      // Skip next
                      _MiniIconButton(
                        icon: Icons.skip_next_rounded,
                        color: Colors.white70,
                        size: 24,
                        onPressed: () =>
                            ref.read(playerProvider.notifier).playNext(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Neon progress bar at bottom ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: StreamBuilder<Duration>(
                  stream: ref.read(playerProvider.notifier).player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total    = Duration(seconds: song.duration);
                    final progress = total.inMilliseconds > 0
                        ? (position.inMilliseconds / total.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return SizedBox(
                      height: 3,
                      child: CustomPaint(
                        painter: _NeonProgressPainter(progress, themeColor),
                        size: const Size(double.infinity, 3),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Glass container shell ─────────────────────────────────────────────────────
class _GlassShell extends StatelessWidget {
  final Widget child;
  const _GlassShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _G.neonA.withOpacity(0.12),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _G.glassShadow,
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.13),
                  Colors.white.withOpacity(0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _G.glassBorder, width: 0.7),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Album thumbnail with neon glow ring ───────────────────────────────────────
class _AlbumThumb extends StatelessWidget {
  final String imageUrl;
  const _AlbumThumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: _G.neonA.withOpacity(0.30),
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
            placeholder: (context, url) => Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: Colors.white24, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glowing play/pause pill ───────────────────────────────────────────────────
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
    return GestureDetector(
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
            colors: [themeColor, themeColor.withOpacity(0.8)],
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
    );
  }
}

// ── Generic mini icon button ──────────────────────────────────────────────────
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;

  const _MiniIconButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(child: Icon(icon, color: color, size: size)),
      ),
    );
  }
}
