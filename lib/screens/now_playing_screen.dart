import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:marquee/marquee.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import 'queue_screen.dart';
import 'package:flutter/foundation.dart';
import '../widgets/options_menu.dart';
import '../models/song.dart';

// ---------------------------------------------------------------------------
// Isolate-safe color extraction
// ---------------------------------------------------------------------------
Future<List<Color>> _extractMeshColors(String imageUrl) async {
  final palette = await PaletteGenerator.fromImageProvider(
    NetworkImage(imageUrl),
    size: const Size(80, 80),
    maximumColorCount: 8,
  );
  return [
    palette.dominantColor?.color ?? const Color(0xFF1C1C1E),
    palette.vibrantColor?.color ?? palette.mutedColor?.color ?? const Color(0xFF000000),
    palette.darkMutedColor?.color ?? const Color(0xFF2C2C2E),
    palette.lightVibrantColor?.color ?? palette.lightMutedColor?.color ?? const Color(0xFF1C1C1E),
  ];
}

// ---------------------------------------------------------------------------
// Animated sound-bar widget (replaces the lyrics button)
// ---------------------------------------------------------------------------
class _SoundBar extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  const _SoundBar({required this.isPlaying, this.color = Colors.white54});

  @override
  State<_SoundBar> createState() => _SoundBarState();
}

class _SoundBarState extends State<_SoundBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _random = math.Random();
  final List<double> _phases = [];

  @override
  void initState() {
    super.initState();
    // Random phase offsets per bar so they don't all bounce in sync
    for (int i = 0; i < 4; i++) {
      _phases.add(_random.nextDouble() * math.pi * 2);
    }
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              // When paused, bars shrink to a flat line
              final t = widget.isPlaying
                  ? (math.sin(_ctrl.value * math.pi * 2 + _phases[i]) + 1) / 2
                  : 0.15;
              final barHeight = (4 + t * 14).toDouble();
              return Container(
                width: 2.5,
                height: barHeight,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Now Playing Screen
// ---------------------------------------------------------------------------
class NowPlayingScreen extends ConsumerStatefulWidget {
  final String? initialImageUrl;
  const NowPlayingScreen({super.key, this.initialImageUrl});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;

  List<Color> _meshColors = [
    const Color(0xFF1C1C1E),
    const Color(0xFF000000),
    const Color(0xFF2C2C2E),
    const Color(0xFF1C1C1E),
  ];
  String? _lastImageUrl;
  bool _meshReady = false;
  bool _transitionFinished = false;
  bool _transitionListenerAttached = false;
  Timer? _transitionFallbackTimer;

  // Sleep timer
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  int? _sleepSecondsRemaining;

  // -------------------------------------------------------------------------
  // BUG-13 FIX: snapshot of last valid song for use during shuffle rebuild gap
  //
  // During the async gap while applyShuffleAlgorithm() rebuilds the audio
  // source, playerState.queue may transiently appear empty (the source reset
  // clears currentIndex).  Instead of showing the black Scaffold fallback we
  // hold onto the last successfully rendered song and keep it visible.
  // -------------------------------------------------------------------------
  Song? _lastKnownSong;
  String? _lastKnownImageUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_transitionFinished || _transitionListenerAttached) return;

    final route = ModalRoute.of(context);
    if (route == null) return;

    void completeTransition() {
      if (!mounted || _transitionFinished) return;
      setState(() => _transitionFinished = true);
      if (widget.initialImageUrl != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadPalette(widget.initialImageUrl!);
          }
        });
      }
    }

    void handler(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        route.animation?.removeStatusListener(handler);
        _transitionFallbackTimer?.cancel();
        completeTransition();
      }
    }

    _transitionListenerAttached = true;
    route.animation?.addStatusListener(handler);
    _transitionFallbackTimer = Timer(const Duration(milliseconds: 460), () {
      route.animation?.removeStatusListener(handler);
      completeTransition();
    });
  }

  @override
  void dispose() {
    _transitionFallbackTimer?.cancel();
    _sleepTimer?.cancel();
    _sleepCountdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPalette(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

    try {
      final colors = await compute(_extractMeshColors, imageUrl);
      if (!mounted) return;
      setState(() {
        _meshColors = colors;
        _meshReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _meshReady = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Sleep timer
  // ---------------------------------------------------------------------------

  void _showSleepTimerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceLevel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Stop Audio In',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...[5, 10, 15, 30, 45, 60].map(
              (mins) => ListTile(
                title: Text('$mins Minutes',
                    style:
                        const TextStyle(color: AppTheme.textPrimary)),
                trailing: _sleepSecondsRemaining != null &&
                        (_sleepSecondsRemaining! / 60).round() == mins
                    ? const Icon(Icons.check_rounded,
                        color: AppTheme.electricBlue, size: 18)
                    : null,
                onTap: () {
                  _setSleepTimer(mins);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('Off',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                _setSleepTimer(null);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepCountdownTimer?.cancel();

    if (minutes == null) {
      setState(() => _sleepSecondsRemaining = null);
      return;
    }

    setState(() => _sleepSecondsRemaining = minutes * 60);

    // Tick every second so the label stays accurate
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_sleepSecondsRemaining != null && _sleepSecondsRemaining! > 0) {
          _sleepSecondsRemaining = _sleepSecondsRemaining! - 1;
        } else {
          t.cancel();
          _sleepSecondsRemaining = null;
        }
      });
    });

    _sleepTimer = Timer(Duration(minutes: minutes), () {
      ref.read(playerProvider.notifier).player.pause();
      _sleepCountdownTimer?.cancel();
      if (mounted) setState(() => _sleepSecondsRemaining = null);
    });
  }

  String _formatSleepLabel() {
    if (_sleepSecondsRemaining == null) return '';
    final mins = _sleepSecondsRemaining! ~/ 60;
    final secs = _sleepSecondsRemaining! % 60;
    if (mins > 0) return '${mins}m';
    return '${secs}s';
  }

  void _showSmartShuffleDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceLevel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Smart Shuffle Mode',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...ShuffleAlgorithm.values.map(
              (algo) => ListTile(
                leading: Icon(
                  algo == ShuffleAlgorithm.standard
                      ? Icons.shuffle_rounded
                      : algo == ShuffleAlgorithm.spotify
                          ? Icons.auto_awesome_rounded
                          : Icons.trending_up_rounded,
                  color: ref.read(settingsProvider).shuffleAlgorithm == algo
                      ? AppTheme.spotifyGreen
                      : Colors.white54,
                ),
                title: Text(algo.name.toUpperCase(),
                    style: const TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(
                  algo == ShuffleAlgorithm.spotify
                      ? 'Balanced dithering (Artist spacing)'
                      : algo == ShuffleAlgorithm.youtube
                          ? 'Weighted lottery (Stars & Playcount)'
                          : 'Standard Fisher-Yates',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: ref.read(settingsProvider).shuffleAlgorithm == algo
                    ? const Icon(Icons.check_rounded,
                        color: AppTheme.spotifyGreen, size: 18)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setShuffleAlgorithm(algo);
                  // If shuffle is already on, re-apply the new algorithm immediately
                  if (ref.read(playerProvider).shuffleMode) {
                    ref.read(playerProvider.notifier).applyShuffleAlgorithm();
                  }
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shuffle / Repeat mode label helper
  // ---------------------------------------------------------------------------
  String _shuffleModeLabel(ShuffleAlgorithm algo) {
    switch (algo) {
      case ShuffleAlgorithm.spotify:
        return 'Balanced';
      case ShuffleAlgorithm.youtube:
        return 'Weighted';
      case ShuffleAlgorithm.standard:
        return 'Shuffle';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final service = ref.watch(subsonicServiceProvider);

    // -------------------------------------------------------------------------
    // BUG-13 FIX: suppress black-screen flash during shuffle rebuild
    //
    // The async gap between setQueue() and the completion of
    // applyShuffleAlgorithm() can produce a frame where queue.isEmpty is
    // true even though music is playing and the screen is visible.  Instead of
    // the pure-black fallback Scaffold we:
    //   1. Keep a _lastKnownSong snapshot that is only updated when the queue
    //      is genuinely populated.
    //   2. During the shuffle gap (notifier.isShuffling == true) we keep
    //      rendering the previous song rather than flashing to black.
    // -------------------------------------------------------------------------
    final bool queueReady =
        playerState.queue.isNotEmpty && playerState.currentIndex < playerState.queue.length;

    if (queueReady) {
      _lastKnownSong = playerState.queue[playerState.currentIndex];
      _lastKnownImageUrl = service.getCoverArtUrl(_lastKnownSong!.coverArt);
    }

    // True empty state — nothing has ever played, or the screen was opened
    // with no queue at all.  Only show the black fallback when we have no
    // snapshot to fall back to AND we are not in the middle of a shuffle rebuild.
    if (!queueReady && _lastKnownSong == null && !notifier.isShuffling) {
      return const Scaffold(
          backgroundColor: AppTheme.coreBackground, body: SizedBox());
    }

    // Use the last known song/image during a transient empty-queue window.
    final song = queueReady
        ? playerState.queue[playerState.currentIndex]
        : _lastKnownSong!;
    final imageUrl = queueReady
        ? service.getCoverArtUrl(song.coverArt)
        : _lastKnownImageUrl!;

    // BUG FIX: Only trigger palette load if the image URL actually changed.
    // Store _lastImageUrl BEFORE calling _loadPalette to avoid infinite loops
    // where the check always returns true on every rebuild.
    if (imageUrl != _lastImageUrl) {
      _lastImageUrl = imageUrl;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadPalette(imageUrl));
    }

    final shuffleAlgo = settings.shuffleAlgorithm;
    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive = playerState.repeatMode != LoopMode.off;
    final shuffleRepeatActive = isShuffleActive || isRepeatActive;

    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _dragOffset =
          (d.primaryDelta! > 0 || _dragOffset > 0)
              ? (_dragOffset + d.primaryDelta!).clamp(0, double.infinity)
              : 0),
      onVerticalDragEnd: (d) =>
          (_dragOffset > 150 || (d.primaryVelocity ?? 0) > 1000)
              ? Navigator.pop(context)
              : setState(() => _dragOffset = 0),
      child: AnimatedContainer(
        duration:
            _dragOffset == 0 ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _dragOffset, 0),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Base dark colour
              const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF1C1C1E))),

              // Mesh gradient (fades in after hero transition)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: (_meshReady && _transitionFinished) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 800),
                  child: _transitionFinished
                      ? AnimatedMeshGradient(
                          colors: _meshColors,
                          options: AnimatedMeshGradientOptions(
                              speed: playerState.isPlaying ? 2 : 0.01, grain: 0.05))
                      : const SizedBox.shrink(),
                ),
              ),

              // Scrim
              Positioned.fill(
                  child: ColoredBox(color: Colors.black.withOpacity(0.28))),

              // Main content
              SafeArea(
                child: Column(
                  children: [
                    // ── Top bar ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.white, size: 32),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.more_horiz_rounded,
                                color: Colors.white54, size: 28),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => OptionsMenu(song: song),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // ── Album art ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                color: AppTheme.surfaceLevel,
                                child: const Icon(Icons.music_note_rounded,
                                    size: 80, color: AppTheme.textMuted)),
                            errorWidget: (_, __, ___) => Container(
                                color: AppTheme.surfaceLevel,
                                child: const Icon(Icons.music_note_rounded,
                                    size: 80, color: AppTheme.textMuted)),
                          ),
                        ),
                      ),
                    ),

                    // ── Song info ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 28,
                                  child: song.title.length > 28
                                      ? Marquee(
                                          text: song.title,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white),
                                          scrollAxis: Axis.horizontal,
                                          blankSpace: 48,
                                          velocity: 30,
                                        )
                                      : Text(
                                          song.title,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist,
                                  style: const TextStyle(
                                      fontSize: 15, color: Colors.white60),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              playerState.starredIds.contains(song.id)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: playerState.starredIds.contains(song.id)
                                  ? Colors.pinkAccent
                                  : Colors.white54,
                              size: 26,
                            ),
                            onPressed: () => ref
                                .read(playerProvider.notifier)
                                .toggleStar(song.id),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Progress bar ───────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: StreamBuilder<Duration>(
                        stream: ref
                            .read(playerProvider.notifier)
                            .player
                            .positionStream,
                        builder: (context, snapshot) {
                          final position =
                              snapshot.data ?? Duration.zero;
                          return ProgressBar(
                            progress: position,
                            total:
                                Duration(seconds: song.duration),
                            onSeek: (d) => ref
                                .read(playerProvider.notifier)
                                .player
                                .seek(d),
                            baseBarColor:
                                Colors.white.withOpacity(0.15),
                            progressBarColor: Colors.white,
                            thumbColor: Colors.white,
                            thumbRadius: 5,
                            barHeight: 3,
                            timeLabelTextStyle: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Transport controls ─────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // ---- Shuffle ----
                          GestureDetector(
                            onLongPress: _showSmartShuffleDialog,
                            child: IconButton(
                              icon: Icon(Icons.shuffle_rounded,
                                  color: isShuffleActive
                                      ? AppTheme.spotifyGreen
                                      : Colors.white54,
                                  size: 24),
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).toggleShuffle(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded,
                                size: 44, color: Colors.white),
                            onPressed: () =>
                                ref.read(playerProvider.notifier).playPrev(),
                          ),
                          GestureDetector(
                            onTap: () => playerState.isPlaying
                                ? ref
                                    .read(playerProvider.notifier)
                                    .player
                                    .pause()
                                : ref
                                    .read(playerProvider.notifier)
                                    .player
                                    .play(),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: Icon(
                                playerState.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 40,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded,
                                size: 44, color: Colors.white),
                            onPressed: () =>
                                ref.read(playerProvider.notifier).playNext(),
                          ),
                          IconButton(
                            icon: Icon(
                                playerState.repeatMode == LoopMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                color: isRepeatActive
                                    ? AppTheme.spotifyGreen
                                    : Colors.white54,
                                size: 24),
                            onPressed: () =>
                                ref.read(playerProvider.notifier).cycleRepeat(),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── Custom bottom bar ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ---- Sound bar ----
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SoundBar(
                                isPlaying: playerState.isPlaying,
                                color: Colors.white54,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                playerState.isPlaying ? 'Playing' : 'Paused',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 9),
                              ),
                            ],
                          ),

                          // ---- Infinity (Autoplay) ----
                          GestureDetector(
                            onTap: () => ref.read(playerProvider.notifier).toggleAutoplay(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.all_inclusive_rounded,
                                  color: playerState.autoplayMode
                                      ? AppTheme.electricBlue
                                      : Colors.white54,
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Infinity',
                                  style: TextStyle(
                                    color: playerState.autoplayMode
                                        ? AppTheme.electricBlue
                                        : Colors.white54,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ---- Sleep timer ----
                          GestureDetector(
                            onTap: _showSleepTimerDialog,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bedtime_outlined,
                                  color: _sleepSecondsRemaining != null
                                      ? AppTheme.electricBlue
                                      : Colors.white54,
                                  size: 22,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _sleepSecondsRemaining != null
                                      ? _formatSleepLabel()
                                      : 'Sleep',
                                  style: TextStyle(
                                    color: _sleepSecondsRemaining != null
                                        ? AppTheme.electricBlue
                                        : Colors.white54,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ---- Queue / History ----
                          IconButton(
                            icon: const Icon(Icons.queue_music_rounded,
                                color: Colors.white54, size: 24),
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const QueueScreen(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}