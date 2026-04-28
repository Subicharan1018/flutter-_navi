import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:marquee/marquee.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../fluid_background.dart';
import '../widgets/options_menu.dart';
import '../models/song.dart';
import '../services/transcoding_service.dart';
import 'package:flutter/foundation.dart';

// =============================================================================
// 1. COLOR EXTRACTION
//    • Larger sample size (200×200) → richer, more accurate palette
//    • Colors are DARKENED + SATURATED before use (Apple Music style)
//    • 4 semantically distinct slots: dominant, vibrant, dark-accent, light-accent
// =============================================================================

Future<List<int>> _extractPaletteIsolate(String imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl),
      size: const Size(200, 200),
      maximumColorCount: 32,
    );

    Color process(Color base, {double satMul = 1.25, double lightMul = 0.48}) {
      final hsl = HSLColor.fromColor(base);
      return hsl
          .withSaturation((hsl.saturation * satMul).clamp(0.08, 1.0))
          .withLightness((hsl.lightness * lightMul).clamp(0.04, 0.34))
          .toColor();
    }

    Color firstNonNull(List<Color?> candidates, Color fallback) {
      for (final c in candidates) {
        if (c != null) return c;
      }
      return fallback;
    }

    final dominant = firstNonNull([
      palette.dominantColor?.color,
      palette.darkVibrantColor?.color,
      palette.darkMutedColor?.color,
      palette.vibrantColor?.color,
      palette.mutedColor?.color,
      palette.lightMutedColor?.color,
    ], const Color(0xFF202022));

    final dominantHsl = HSLColor.fromColor(dominant);
    final derivedVibrant = dominantHsl
        .withSaturation((dominantHsl.saturation + 0.25).clamp(0.20, 1.0))
        .withLightness((dominantHsl.lightness * 0.95).clamp(0.08, 0.48))
        .toColor();
    final derivedAccent = dominantHsl
        .withSaturation((dominantHsl.saturation + 0.12).clamp(0.14, 1.0))
        .withLightness((dominantHsl.lightness * 1.18).clamp(0.12, 0.58))
        .toColor();

    final vibrant = firstNonNull([
      palette.vibrantColor?.color,
      palette.darkVibrantColor?.color,
      palette.lightVibrantColor?.color,
      palette.mutedColor?.color,
    ], derivedVibrant);

    final darkAccent = firstNonNull([
      palette.darkMutedColor?.color,
      palette.darkVibrantColor?.color,
      palette.mutedColor?.color,
      palette.dominantColor?.color,
    ], dominant);

    final lightAccent = firstNonNull([
      palette.lightVibrantColor?.color,
      palette.lightMutedColor?.color,
      palette.vibrantColor?.color,
      palette.mutedColor?.color,
    ], derivedAccent);

    return [
      process(dominant, satMul: 1.10, lightMul: 0.44).value,
      process(vibrant, satMul: 1.35, lightMul: 0.52).value,
      process(darkAccent, satMul: 1.05, lightMul: 0.40).value,
      process(lightAccent, satMul: 1.20, lightMul: 0.58).value,
    ];
  } catch (_) {
    return [0xFF121212, 0xFF1D1D1D, 0xFF0B0B0B, 0xFF2A2A2A];
  }
}

List<Color> _intsToColors(List<int> v) => v.map((i) => Color(i)).toList();

// =============================================================================
// 2. SMALL REUSABLE WIDGETS
//    _SoundBar  –  animated equalizer bars
//    _BottomAction  –  icon + label tap target used in the bottom row
// =============================================================================

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
  final _rng = math.Random();
  final List<double> _phases = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 4; i++) _phases.add(_rng.nextDouble() * math.pi * 2);
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
    return RepaintBoundary(
      child: SizedBox(
        width: 20,
        height: 20,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              final t = widget.isPlaying
                  ? (math.sin(_ctrl.value * math.pi * 2 + _phases[i]) + 1) / 2
                  : 0.15;
              return Container(
                width: 2.5,
                height: (4 + t * 14).toDouble(),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 9,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 3. AUDIO QUALITY STRIP
//    Shows source format/bitrate and active transcoding override.
// =============================================================================

class _AudioQualityStrip extends ConsumerWidget {
  final Song song;
  const _AudioQualityStrip({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcoding = ref.watch(transcodingProvider);

    final sourceSuffix  = song.suffix.toUpperCase();
    final sourceBitrate = song.bitRate;

    final activeBitrate = transcoding.getCurrentBitrate();
    final activeFormat  = transcoding.getCurrentFormat();
    final isTranscoding = transcoding.enabled &&
        (activeBitrate != null || activeFormat != null);
    final isWifi =
        transcoding.currentConnectionType == ConnectionType.wifi;

    if (sourceSuffix.isEmpty && sourceBitrate == 0 && !isTranscoding) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (sourceSuffix.isNotEmpty || sourceBitrate > 0)
            _QualityPill(
              icon: Icons.audio_file_outlined,
              label: [
                if (sourceSuffix.isNotEmpty) sourceSuffix,
                if (sourceBitrate > 0) '${sourceBitrate} kbps',
              ].join(' · '),
              color: Colors.white38,
            ),
          if ((sourceSuffix.isNotEmpty || sourceBitrate > 0) && isTranscoding)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded,
                  color: Colors.white24, size: 12),
            ),
          if (isTranscoding)
            _QualityPill(
              icon: isWifi
                  ? Icons.wifi_rounded
                  : Icons.signal_cellular_alt_rounded,
              label: [
                if (activeFormat != null)
                  TranscodeFormat.getLabel(activeFormat),
                if (activeBitrate != null) '$activeBitrate kbps',
              ].join(' · '),
              color: AppTheme.electricBlue.withValues(alpha: 0.85),
              highlighted: true,
            ),
        ],
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool highlighted;

  const _QualityPill({
    required this.icon,
    required this.label,
    required this.color,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? AppTheme.electricBlue.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight:
                  highlighted ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. NOW PLAYING SCREEN
// =============================================================================

class NowPlayingScreen extends ConsumerStatefulWidget {
  final String? initialImageUrl;
  const NowPlayingScreen({super.key, this.initialImageUrl});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  // ── Drag-to-dismiss state ────────────────────────────────────────────────
  double _dragOffset = 0;

  // ── Route-transition tracking ────────────────────────────────────────────
  bool _transitionFinished = false;
  bool _transitionListenerAttached = false;
  Timer? _transitionFallbackTimer;

  // ── Sleep timer ──────────────────────────────────────────────────────────
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  // BUG-30: ValueNotifier so 1 Hz tick only rebuilds the sleep-label widget.
  final ValueNotifier<int?> _sleepSeconds = ValueNotifier(null);

  // ── Last-known song cache (keeps UI alive while queue swaps) ─────────────
  Song?   _lastKnownSong;
  String? _lastKnownImageUrl;

  // ── Palette / blob colors ────────────────────────────────────────────────
  List<Color> _blobColors = const [
    Color(0xFF1A1A2E), Color(0xFF16213E),
    Color(0xFF0F3460), Color(0xFF533483),
  ];
  String? _lastPaletteSongId;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_transitionFinished || _transitionListenerAttached) return;
    final route = ModalRoute.of(context);
    if (route == null) return;

    void completeTransition() {
      if (!mounted || _transitionFinished) return;
      setState(() => _transitionFinished = true);
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
    _sleepSeconds.dispose(); // BUG-30
    super.dispose();
  }

  // ── Palette extraction ───────────────────────────────────────────────────

  void _triggerPaletteExtraction(String songId, String imageUrl) {
    if (_lastPaletteSongId == songId) return;
    _lastPaletteSongId = songId;
    // CRIT-2: Do NOT use compute() — PaletteGenerator needs the main isolate's
    // Flutter engine. Direct call is fast; image is already in disk cache.
    _extractPaletteIsolate(imageUrl).then((ints) {
      if (!mounted || _lastPaletteSongId != songId) return;
      setState(() => _blobColors = _intsToColors(ints));
    }).catchError((_) {});
  }

  // ── Sleep timer ──────────────────────────────────────────────────────────

  void _showSleepTimerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceLevel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
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
            ...[5, 10, 15, 30, 45, 60].map((mins) => ListTile(
                  title: Text('$mins Minutes',
                      style: const TextStyle(color: AppTheme.textPrimary)),
                  trailing: _sleepSeconds.value != null &&
                          (_sleepSeconds.value! / 60).round() == mins
                      ? const Icon(Icons.check_rounded,
                          color: AppTheme.electricBlue, size: 18)
                      : null,
                  onTap: () {
                    _setSleepTimer(mins);
                    Navigator.pop(ctx);
                  },
                )),
            ListTile(
              title: const Text('Off',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                _setSleepTimer(null);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepCountdownTimer?.cancel();
    if (minutes == null) {
      _sleepSeconds.value = null;
      return;
    }
    _sleepSeconds.value = minutes * 60;
    _sleepCountdownTimer =
        Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final remaining = _sleepSeconds.value;
      if (remaining != null && remaining > 0) {
        _sleepSeconds.value = remaining - 1;
      } else {
        t.cancel();
        _sleepSeconds.value = null;
      }
    });
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      ref.read(playerProvider.notifier).player.pause();
      _sleepCountdownTimer?.cancel();
      _sleepSeconds.value = null;
    });
  }

  // BUG-30: called from ValueListenableBuilder — no setState needed.
  String _formatSleepLabel(int remaining) {
    final mins = remaining ~/ 60;
    final secs = remaining % 60;
    return mins > 0 ? '${mins}m' : '${secs}s';
  }

  // ── Smart-shuffle dialog ─────────────────────────────────────────────────

  void _showSmartShuffleDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceLevel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
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
            ...ShuffleAlgorithm.values.map((algo) {
              final isSelected =
                  ref.read(settingsProvider).shuffleAlgorithm == algo;
              return ListTile(
                leading: Icon(
                  algo == ShuffleAlgorithm.standard
                      ? Icons.shuffle_rounded
                      : algo == ShuffleAlgorithm.spotify
                          ? Icons.auto_awesome_rounded
                          : Icons.trending_up_rounded,
                  color: isSelected
                      ? AppTheme.spotifyGreen
                      : Colors.white54,
                ),
                title: Text(algo.name.toUpperCase(),
                    style:
                        const TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(
                  algo == ShuffleAlgorithm.spotify
                      ? 'Balanced dithering (Artist spacing)'
                      : algo == ShuffleAlgorithm.youtube
                          ? 'Weighted lottery (Stars & Playcount)'
                          : 'Standard Fisher-Yates',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: AppTheme.spotifyGreen, size: 18)
                    : null,
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setShuffleAlgorithm(algo);
                  if (ref.read(playerProvider).shuffleMode) {
                    ref
                        .read(playerProvider.notifier)
                        .applyShuffleAlgorithm();
                  }
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier    = ref.read(playerProvider.notifier);
    final service     = ref.read(subsonicServiceProvider);

    final bool queueReady = playerState.queue.isNotEmpty &&
        playerState.currentIndex < playerState.queue.length;

    if (queueReady) {
      _lastKnownSong     = playerState.queue[playerState.currentIndex];
      _lastKnownImageUrl = service.getCoverArtUrl(_lastKnownSong!.coverArt);
    }

    if (!queueReady && _lastKnownSong == null && !notifier.isShuffling) {
      return const Scaffold(
          backgroundColor: AppTheme.coreBackground, body: SizedBox());
    }

    final song = queueReady
        ? playerState.queue[playerState.currentIndex]
        : _lastKnownSong!;
    final imageUrl = queueReady
        ? service.getCoverArtUrl(song.coverArt)
        : _lastKnownImageUrl!;
    final cacheKey = 'cover_${song.coverArt ?? song.id}';

    if (_transitionFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerPaletteExtraction(song.id, imageUrl);
      });
    }

    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive  = playerState.repeatMode != LoopMode.off;

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
        duration: _dragOffset == 0
            ? const Duration(milliseconds: 250)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _dragOffset, 0),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background ──────────────────────────────────────────────
              if (_transitionFinished)
                FluidBackground(colors: _blobColors)
              else
                const ColoredBox(color: Colors.black),

              // ── Foreground ──────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // Pull handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ── Top bar: back + overflow ────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 32),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.more_horiz_rounded,
                                color: Colors.white60, size: 28),
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => OptionsMenu(song: song),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Album art ───────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 10),
                      child: AnimatedScale(
                        scale: playerState.isPlaying ? 1.0 : 0.93,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeInOutCubic,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.70),
                                  blurRadius: 44,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 18),
                                ),
                                if (_blobColors.length > 1)
                                  BoxShadow(
                                    color: _blobColors[1]
                                        .withOpacity(0.35),
                                    blurRadius: 60,
                                    offset: const Offset(0, 10),
                                  ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                cacheKey: cacheKey,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    color: AppTheme.surfaceLevel,
                                    child: const Icon(
                                        Icons.music_note_rounded,
                                        size: 80,
                                        color: AppTheme.textMuted)),
                                errorWidget: (_, __, ___) => Container(
                                    color: AppTheme.surfaceLevel,
                                    child: const Icon(
                                        Icons.music_note_rounded,
                                        size: 80,
                                        color: AppTheme.textMuted)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Song info + favourite ───────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 12, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 30,
                                  child: song.title.length > 26
                                      ? Marquee(
                                          text: song.title,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: Colors.white,
                                              letterSpacing: -0.3),
                                          scrollAxis: Axis.horizontal,
                                          blankSpace: 52,
                                          velocity: 28,
                                        )
                                      : Text(
                                          song.title,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: Colors.white,
                                              letterSpacing: -0.3),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist,
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white
                                          .withOpacity(0.65),
                                      fontWeight: FontWeight.w400),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Favourite button
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: AnimatedSwitcher(
                                duration:
                                    const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                        scale: anim, child: child),
                                child: Icon(
                                  playerState.starredIds
                                          .contains(song.id)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(playerState.starredIds
                                      .contains(song.id)),
                                  color: playerState.starredIds
                                          .contains(song.id)
                                      ? Colors.pinkAccent
                                      : Colors.white54,
                                  size: 26,
                                ),
                              ),
                              onPressed: () => ref
                                  .read(playerProvider.notifier)
                                  .toggleStar(song.id),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ── Progress bar ────────────────────────────────────
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32),
                        child: StreamBuilder<Duration>(
                          stream: notifier.player.positionStream,
                          builder: (context, snapshot) {
                            final position =
                                snapshot.data ?? Duration.zero;
                            return ProgressBar(
                              progress: position,
                              total: Duration(seconds: song.duration),
                              onSeek: (d) =>
                                  notifier.player.seek(d),
                              baseBarColor:
                                  Colors.white.withOpacity(0.18),
                              progressBarColor: Colors.white,
                              thumbColor: Colors.white,
                              thumbRadius: 6,
                              barHeight: 4,
                              timeLabelTextStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Audio quality strip ─────────────────────────────
                    _AudioQualityStrip(song: song),

                    const SizedBox(height: 36),

                    // ── Transport controls ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Shuffle (long-press → smart-shuffle dialog)
                          GestureDetector(
                            onLongPress: _showSmartShuffleDialog,
                            child: IconButton(
                              icon: Icon(Icons.shuffle_rounded,
                                  color: isShuffleActive
                                      ? AppTheme.spotifyGreen
                                      : Colors.white54,
                                  size: 26),
                              onPressed: () =>
                                  notifier.toggleShuffle(),
                            ),
                          ),
                          // Previous
                          IconButton(
                            icon: const Icon(
                                Icons.skip_previous_rounded,
                                size: 48,
                                color: Colors.white),
                            onPressed: () => notifier.playPrev(),
                          ),
                          // Play / Pause
                          GestureDetector(
                            onTap: () => playerState.isPlaying
                                ? notifier.player.pause()
                                : notifier.player.play(),
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.white.withOpacity(0.22),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: AnimatedSwitcher(
                                duration:
                                    const Duration(milliseconds: 180),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                        scale: anim, child: child),
                                child: Icon(
                                  playerState.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  key: ValueKey(playerState.isPlaying),
                                  size: 42,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                          // Next
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded,
                                size: 48, color: Colors.white),
                            onPressed: () => notifier.playNext(),
                          ),
                          // Repeat
                          IconButton(
                            icon: Icon(
                                playerState.repeatMode == LoopMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                color: isRepeatActive
                                    ? AppTheme.spotifyGreen
                                    : Colors.white54,
                                size: 26),
                            onPressed: () => notifier.cycleRepeat(),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── Bottom actions ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        children: [
                          _BottomAction(
                            icon: _SoundBar(
                                isPlaying: playerState.isPlaying,
                                color: Colors.white70),
                            label: playerState.isPlaying
                                ? 'Playing'
                                : 'Paused',
                            labelColor: Colors.white38,
                            onTap: () {},
                          ),
                          _BottomAction(
                            icon: Icon(Icons.all_inclusive_rounded,
                                color: playerState.autoplayMode
                                    ? AppTheme.electricBlue
                                    : Colors.white70,
                                size: 24),
                            label: 'Autoplay',
                            labelColor: playerState.autoplayMode
                                ? AppTheme.electricBlue
                                : Colors.white54,
                            onTap: () => notifier.toggleAutoplay(),
                          ),
                          // BUG-30: scopes 1 Hz rebuild to just this label.
                          ValueListenableBuilder<int?>(
                            valueListenable: _sleepSeconds,
                            builder: (_, remaining, __) => _BottomAction(
                              icon: Icon(Icons.bedtime_outlined,
                                  color: remaining != null
                                      ? AppTheme.electricBlue
                                      : Colors.white70,
                                  size: 24),
                              label: remaining != null
                                  ? _formatSleepLabel(remaining)
                                  : 'Sleep',
                              labelColor: remaining != null
                                  ? AppTheme.electricBlue
                                  : Colors.white54,
                              onTap: _showSleepTimerDialog,
                            ),
                          ),
                          _BottomAction(
                            icon: const Icon(Icons.queue_music_rounded,
                                color: Colors.white70, size: 24),
                            label: 'Queue',
                            labelColor: Colors.white54,
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const QueueScreen(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
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

// =============================================================================
// 5. QUEUE SCREEN
// =============================================================================

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier    = ref.read(playerProvider.notifier);
    final service     = ref.read(subsonicServiceProvider);

    final upNext      = playerState.upNext;
    final history     = playerState.historySongs;
    final currentSong = playerState.currentSong;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceLevel,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Queue',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3)),
                        const Spacer(),
                        AnimatedBuilder(
                          animation: _tabs,
                          builder: (_, __) {
                            if (_tabs.index != 1 || history.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return TextButton(
                              onPressed: () =>
                                  notifier.clearHistory(),
                              child: const Text('Clear',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13)),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Tab bar
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: TabBar(
                        controller: _tabs,
                        indicator: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white38,
                        labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(
                                    Icons.queue_music_rounded,
                                    size: 14),
                                const SizedBox(width: 5),
                                Text('Up Next (${upNext.length})'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.history_rounded,
                                    size: 14),
                                const SizedBox(width: 5),
                                Text(
                                    'History (${history.length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),

              // ── Now-playing strip ────────────────────────────────────
              if (currentSong != null) ...[
                _NowPlayingStrip(song: currentSong, service: service),
                const Divider(color: Colors.white10, height: 1),
              ],

              // ── Tab content ──────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // Up Next
                    upNext.isEmpty
                        ? const _EmptyTab(
                            icon: Icons.queue_music_rounded,
                            label: 'Nothing up next')
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            padding:
                                const EdgeInsets.only(bottom: 120),
                            itemCount: upNext.length,
                            onReorder: (oldIdx, newIdx) {
                              final qOld = playerState.currentIndex +
                                  1 +
                                  oldIdx;
                              final qNew = playerState.currentIndex +
                                  1 +
                                  newIdx;
                              notifier.reorderQueue(qOld, qNew);
                            },
                            itemBuilder: (context, i) {
                              final s    = upNext[i];
                              final qIdx =
                                  playerState.currentIndex + 1 + i;
                              return _QueueTile(
                                key: ValueKey('nxt_${s.id}_$i'),
                                song: s,
                                service: service,
                                onTap: () {
                                  notifier.jumpTo(qIdx);
                                  Navigator.pop(context);
                                },
                                onRemove: () =>
                                    notifier.removeFromQueue(qIdx),
                                dragHandle:
                                    ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: Colors.white30,
                                        size: 20),
                                  ),
                                ),
                              );
                            },
                          ),

                    // History
                    history.isEmpty
                        ? const _EmptyTab(
                            icon: Icons.history_rounded,
                            label: 'No songs played yet')
                        : ListView.builder(
                            padding:
                                const EdgeInsets.only(bottom: 120),
                            itemCount: history.length,
                            itemBuilder: (context, i) {
                              final song =
                                  history[history.length - 1 - i];
                              return _HistoryTile(
                                key: ValueKey('hist_${song.id}_$i'),
                                song: song,
                                service: service,
                                isNewest: i == 0,
                                onTap: () {
                                  final qIdx = playerState.queue
                                      .lastIndexWhere(
                                          (s) => s.id == song.id);
                                  if (qIdx >= 0) {
                                    notifier.jumpTo(qIdx);
                                  } else {
                                    notifier.setQueue([song], 0);
                                  }
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// 6. QUEUE SCREEN SUB-WIDGETS
//    _NowPlayingStrip  –  currently-playing row inside the queue sheet
//    _MiniSoundBars    –  small animated equalizer for the strip
//    _QueueTile        –  draggable / dismissible "up next" row
//    _HistoryTile      –  history row with "last played" badge
//    _EmptyTab         –  placeholder shown when a tab list is empty
// =============================================================================

class _NowPlayingStrip extends StatelessWidget {
  final Song song;
  final dynamic service;
  const _NowPlayingStrip({required this.song, required this.service});

  @override
  Widget build(BuildContext context) {
    final url = service.getCoverArtUrl(song.coverArt) as String;
    final key = 'cover_${song.coverArt ?? song.id}';
    return Container(
      color: Colors.white.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: key,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: AppTheme.surfaceLevel,
                  child: const Icon(Icons.music_note_rounded,
                      color: AppTheme.textMuted, size: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const _MiniSoundBars(),
        ],
      ),
    );
  }
}

class _MiniSoundBars extends StatefulWidget {
  const _MiniSoundBars();

  @override
  State<_MiniSoundBars> createState() => _MiniSoundBarsState();
}

class _MiniSoundBarsState extends State<_MiniSoundBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = math.Random();
  final List<double> _phases = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) _phases.add(_rng.nextDouble() * math.pi * 2);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => SizedBox(
          width: 18,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final t =
                  (math.sin(_ctrl.value * math.pi * 2 + _phases[i]) + 1) /
                      2;
              return Container(
                width: 2.5,
                height: (3 + t * 11).toDouble(),
                decoration: BoxDecoration(
                  color: AppTheme.spotifyGreen,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Song song;
  final dynamic service;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final Widget dragHandle;

  const _QueueTile({
    super.key,
    required this.song,
    required this.service,
    required this.onTap,
    required this.onRemove,
    required this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final url = service.getCoverArtUrl(song.coverArt) as String;
    final key = 'cover_${song.coverArt ?? song.id}';
    return Dismissible(
      key: ValueKey('dis_q_${song.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.transparent,
            Colors.redAccent.withOpacity(0.80),
          ]),
        ),
        child: const Icon(Icons.remove_circle_outline_rounded,
            color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: CachedNetworkImage(
            imageUrl: url,
            cacheKey: key,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
                width: 44,
                height: 44,
                color: AppTheme.surfaceLevel,
                child: const Icon(Icons.music_note_rounded,
                    color: AppTheme.textMuted, size: 20)),
          ),
        ),
        title: Text(song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: dragHandle,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Song song;
  final dynamic service;
  final bool isNewest;
  final VoidCallback onTap;

  const _HistoryTile({
    super.key,
    required this.song,
    required this.service,
    required this.isNewest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final url = service.getCoverArtUrl(song.coverArt) as String;
    final key = 'cover_${song.coverArt ?? song.id}';
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: key,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: AppTheme.surfaceLevel,
                  child: const Icon(Icons.music_note_rounded,
                      color: AppTheme.textMuted, size: 20)),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomRight: Radius.circular(5)),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white70, size: 11),
            ),
          ),
        ],
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: isNewest
                  ? Colors.white
                  : Colors.white.withOpacity(0.72),
              fontSize: 14,
              fontWeight:
                  isNewest ? FontWeight.w600 : FontWeight.w400)),
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: isNewest
                  ? Colors.white60
                  : Colors.white.withOpacity(0.36),
              fontSize: 12)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(Icons.history_rounded,
              color: Colors.white.withOpacity(0.22), size: 15),
          if (isNewest)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Last played',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 9)),
            ),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              color: Colors.white.withOpacity(0.15), size: 54),
          const SizedBox(height: 14),
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 15)),
        ],
      ),
    );
  }
}