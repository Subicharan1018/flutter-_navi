import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
// dart:isolate removed — PaletteGenerator.fromImageProvider requires the
// Flutter engine's image codec which is unavailable in bare Dart isolates.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../core/palette_cache.dart';
import '../fluid_background.dart';
import '../widgets/options_menu.dart';
import '../models/song.dart';
import '../services/subsonic_service.dart';
import '../services/transcoding_service.dart';
import 'package:flutter/foundation.dart';
import '../lyrics/views/lyrics_view.dart';

// =============================================================================
// 1. COLOR EXTRACTION
// =============================================================================

// CRIT-FIX: PaletteGenerator.fromImageProvider uses Flutter's image codec
// which requires the main isolate's Flutter engine. Using Isolate.run()
// spawns a bare Dart isolate where the codec is unavailable, causing silent
// failures and returning the dark fallback (black gradient).
// Fix: run directly on the main isolate; use CachedNetworkImageProvider so
// the cached image is reused rather than re-downloaded.
Future<List<int>> _extractPaletteIsolate(String imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl),
      size: const Size(100, 100),
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
// =============================================================================

class _SoundBar extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  const _SoundBar({
    required this.isPlaying,
    this.color = const Color(0x8AFFFFFF),
  });

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
    for (int i = 0; i < 4; i++) {
      _phases.add(_rng.nextDouble() * math.pi * 2);
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
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
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
      ),
    );
  }
}

// =============================================================================
// 3. AUDIO QUALITY STRIP
// =============================================================================

class _AudioQualityStrip extends ConsumerWidget {
  final Song song;
  const _AudioQualityStrip({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcoding = ref.watch(transcodingProvider);

    final sourceSuffix = song.suffix.toUpperCase();
    final sourceBitrate = song.bitRate;

    final activeBitrate = transcoding.getCurrentBitrate();
    final activeFormat = transcoding.getCurrentFormat();
    final isTranscoding =
        transcoding.enabled && (activeBitrate != null || activeFormat != null);
    final isWifi = transcoding.currentConnectionType == ConnectionType.wifi;

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
                if (sourceBitrate > 0) '$sourceBitrate kbps',
              ].join(' · '),
              color: ThemeTokens.of(context).textMuted,
            ),
          if ((sourceSuffix.isNotEmpty || sourceBitrate > 0) && isTranscoding)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: ThemeTokens.of(context).textMuted.withOpacity(0.5),
                size: 12,
              ),
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
              color: ThemeTokens.of(context).accent.withValues(alpha: 0.85),
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
            ? ThemeTokens.of(context).accent.withValues(alpha: 0.12)
            : ThemeTokens.of(context).textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
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
              fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. VOLUME SLIDER
// =============================================================================

class _VolumeSlider extends StatefulWidget {
  final AudioPlayer player;
  const _VolumeSlider({required this.player});

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double _volume = 1.0;
  double _lastHapticVolume = -1;

  // FIX BUG-5: Subscribe to volumeStream so the slider stays in sync when
  // volume changes externally (hardware buttons, system audio ducking, etc.).
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.volume;
    _volumeSub = widget.player.volumeStream.listen((v) {
      if (mounted && (v - _volume).abs() > 0.005) {
        setState(() => _volume = v);
      }
    });
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    super.dispose();
  }

  void _onChanged(double v) {
    setState(() => _volume = v);
    widget.player.setVolume(v);

    final snaps = [0.0, 0.5, 1.0];
    for (final snap in snaps) {
      if ((_lastHapticVolume - snap).abs() > 0.01 && (v - snap).abs() < 0.015) {
        HapticFeedback.selectionClick();
        _lastHapticVolume = snap;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Icon(
            _volume < 0.02
                ? Icons.volume_off_rounded
                : Icons.volume_down_rounded,
            color: ThemeTokens.of(context).textSecondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: ThemeTokens.of(context).textPrimary,
                  inactiveTrackColor: ThemeTokens.of(
                    context,
                  ).textPrimary.withOpacity(0.20),
                  thumbColor: Colors.transparent,
                  thumbShape: _AppleMusicThumb(
                    color: ThemeTokens.of(context).textPrimary,
                    shadowColor: ThemeTokens.of(
                      context,
                    ).bgOverlay.withOpacity(0.35),
                  ),
                  overlayColor: Colors.transparent,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                  trackShape: _RoundedTrackShape(),
                ),
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: _onChanged,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.volume_up_rounded,
            color: ThemeTokens.of(context).textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _RoundedTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class _AppleMusicThumb extends SliderComponentShape {
  final Color color;
  final Color shadowColor;

  _AppleMusicThumb({required this.color, required this.shadowColor});

  @override
  Size getPreferredSize(bool isEnabled, bool isInteractive) =>
      const Size(4, 22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    const w = 4.0;
    const h = 22.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      rect.shift(const Offset(0, 1.5)),
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }
}

// =============================================================================
// 5. NOW PLAYING SCREEN
// =============================================================================

class NowPlayingScreen extends ConsumerStatefulWidget {
  final String? initialImageUrl;
  const NowPlayingScreen({super.key, this.initialImageUrl});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;

  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  final ValueNotifier<int?> _sleepSeconds = ValueNotifier(null);

  Song? _lastKnownSong;
  String? _lastKnownImageUrl;

  List<Color> _blobColors = PaletteCache.instance.colors;

  // FIX BUG-3: Track the last song ID for which extraction was triggered so
  // we only call _triggerPaletteExtraction once per song, not once per build.
  String? _lastExtractedSongId;
  String? _inflightSongId;

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepCountdownTimer?.cancel();
    _sleepSeconds.dispose();
    super.dispose();
  }

  // ── Palette extraction ───────────────────────────────────────────────────

  void _triggerPaletteExtraction(String songId, String imageUrl) {
    // FIX BUG-3: Guard against re-triggering on every build for the same song.
    if (_lastExtractedSongId == songId) return;

    if (PaletteCache.instance.hasColorsFor(songId)) {
      _lastExtractedSongId = songId;
      if (!listEquals(_blobColors, PaletteCache.instance.colors)) {
        setState(() => _blobColors = PaletteCache.instance.colors);
      }
      return;
    }

    if (_inflightSongId == songId) return;
    _lastExtractedSongId = songId;
    _inflightSongId = songId;

    _extractPaletteIsolate(imageUrl)
        .then((ints) {
          if (!mounted || _inflightSongId != songId) return;
          final colors = _intsToColors(ints);
          PaletteCache.instance.update(songId, colors);
          setState(() => _blobColors = colors);
        })
        .catchError((_) {
          _inflightSongId = null;
        });
  }

  // ── Sleep timer ──────────────────────────────────────────────────────────

  void _showSleepTimerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // FIX BUG-4: Wrap the builder in a ValueListenableBuilder so the
      // checkmark reacts to _sleepSeconds changes while the sheet is open.
      // Without this, the trailing icon is evaluated once at open time and
      // never re-reads the notifier.
      builder: (ctx) => ValueListenableBuilder<int?>(
        valueListenable: _sleepSeconds,
        builder: (_, remaining, __) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Stop Audio In',
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...[5, 10, 15, 30, 45, 60].map(
                (mins) => ListTile(
                  title: Text(
                    '$mins Minutes',
                    style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                    ),
                  ),
                  trailing:
                      remaining != null && (remaining / 60).round() == mins
                      ? Icon(
                          Icons.check_rounded,
                          color: ThemeTokens.of(context).accent,
                          size: 18,
                        )
                      : null,
                  onTap: () {
                    _setSleepTimer(mins);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              ListTile(
                title: const Text(
                  'Off',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  _setSleepTimer(null);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
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

  String _formatSleepLabel(int remaining) {
    final mins = remaining ~/ 60;
    final secs = remaining % 60;
    return mins > 0 ? '${mins}m' : '${secs}s';
  }

  // ── Smart-shuffle dialog ─────────────────────────────────────────────────

  void _showSmartShuffleDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              'Smart Shuffle Mode',
              style: TextStyle(
                color: ThemeTokens.of(context).textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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
                      ? ThemeTokens.of(context).accent
                      : ThemeTokens.of(context).textSecondary,
                ),
                title: Text(
                  algo.name.toUpperCase(),
                  style: TextStyle(color: ThemeTokens.of(context).textPrimary),
                ),
                subtitle: Text(
                  algo == ShuffleAlgorithm.spotify
                      ? 'Balanced dithering (Artist spacing)'
                      : algo == ShuffleAlgorithm.youtube
                      ? 'Weighted lottery (Stars & Playcount)'
                      : 'Standard Fisher-Yates',
                  style: TextStyle(
                    color: ThemeTokens.of(context).textMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        color: ThemeTokens.of(context).accent,
                        size: 18,
                      )
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setShuffleAlgorithm(algo);
                  if (ref.read(playerProvider).shuffleMode) {
                    ref.read(playerProvider.notifier).applyShuffleAlgorithm();
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
    final notifier = ref.read(playerProvider.notifier);
    // FIX BUG-6: Use typed SubsonicService instead of dynamic.
    final service = ref.read(subsonicServiceProvider);

    final bool queueReady =
        playerState.queue.isNotEmpty &&
        playerState.currentIndex < playerState.queue.length;

    if (queueReady) {
      _lastKnownSong = playerState.queue[playerState.currentIndex];
      _lastKnownImageUrl = service.getCoverArtUrl(_lastKnownSong!.coverArt);
    }

    if (!queueReady && _lastKnownSong == null && !notifier.isShuffling) {
      return Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: const SizedBox(),
      );
    }

    final song = queueReady
        ? playerState.queue[playerState.currentIndex]
        : _lastKnownSong!;
    final imageUrl = queueReady
        ? service.getCoverArtUrl(song.coverArt)
        : _lastKnownImageUrl!;
    final cacheKey = 'cover_${song.coverArt ?? song.id}';

    // FIX BUG-3: Only schedule extraction when the song actually changes.
    // The guard inside _triggerPaletteExtraction makes this safe to call
    // from build, but we additionally avoid the addPostFrameCallback overhead
    // on every frame by checking song.id first.
    if (_lastExtractedSongId != song.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerPaletteExtraction(song.id, imageUrl);
      });
    }

    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive = playerState.repeatMode != LoopMode.off;

    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(
        () => _dragOffset = (d.primaryDelta! > 0 || _dragOffset > 0)
            ? (_dragOffset + d.primaryDelta!).clamp(0, double.infinity)
            : 0,
      ),
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
          backgroundColor: ThemeTokens.of(context).bgBase,
          body: Stack(
            fit: StackFit.expand,
            children: [
              FluidBackground(colors: _blobColors),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ThemeTokens.of(
                            context,
                          ).textPrimary.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: ThemeTokens.of(context).textPrimary,
                              size: 32,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              color: ThemeTokens.of(
                                context,
                              ).textPrimary.withOpacity(0.6),
                              size: 28,
                            ),
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
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 10,
                        ),
                        child: RepaintBoundary(
                          child: AnimatedScale(
                            scale: playerState.isPlaying ? 1.0 : 0.93,
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeInOutCubic,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ThemeTokens.of(
                                          context,
                                        ).bgBase.withOpacity(0.70),
                                        blurRadius: 44,
                                        spreadRadius: 4,
                                        offset: const Offset(0, 18),
                                      ),
                                      if (_blobColors.length > 1)
                                        BoxShadow(
                                          color: _blobColors[1].withOpacity(
                                            0.35,
                                          ),
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
                                        color: ThemeTokens.of(
                                          context,
                                        ).bgSurface,
                                        child: Icon(
                                          Icons.music_note_rounded,
                                          size: 80,
                                          color: ThemeTokens.of(
                                            context,
                                          ).textMuted,
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: ThemeTokens.of(
                                          context,
                                        ).bgSurface,
                                        child: Icon(
                                          Icons.music_note_rounded,
                                          size: 80,
                                          color: ThemeTokens.of(
                                            context,
                                          ).textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 12, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 30,
                                  child: song.title.length > 26
                                      ? Marquee(
                                          text: song.title,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: ThemeTokens.of(
                                              context,
                                            ).textPrimary,
                                            letterSpacing: -0.3,
                                          ),
                                          scrollAxis: Axis.horizontal,
                                          blankSpace: 52,
                                          velocity: 28,
                                        )
                                      : Text(
                                          song.title,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: ThemeTokens.of(
                                              context,
                                            ).textPrimary,
                                            letterSpacing: -0.3,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: ThemeTokens.of(
                                      context,
                                    ).textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  playerState.starredIds.contains(song.id)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(
                                    playerState.starredIds.contains(song.id),
                                  ),
                                  color:
                                      playerState.starredIds.contains(song.id)
                                      ? Colors.pinkAccent
                                      : ThemeTokens.of(context).textSecondary,
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
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: _PositionStream(
                          player: notifier.player,
                          songId: song.id,
                          duration: Duration(seconds: song.duration),
                          onSeek: (d) => notifier.player.seek(d),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AudioQualityStrip(song: song),
                    const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Semantics(
                            button: true,
                            label: isShuffleActive
                                ? 'Disable Shuffle'
                                : 'Enable Shuffle',
                            child: GestureDetector(
                              onLongPress: _showSmartShuffleDialog,
                              child: IconButton(
                                tooltip: isShuffleActive
                                    ? 'Disable Shuffle'
                                    : 'Enable Shuffle',
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: isShuffleActive
                                      ? ThemeTokens.of(context).accent
                                      : ThemeTokens.of(context).textSecondary,
                                  size: 26,
                                ),
                                onPressed: () => notifier.toggleShuffle(),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Skip Previous',
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              size: 48,
                              color: ThemeTokens.of(context).textPrimary,
                            ),
                            onPressed: () => notifier.playPrev(),
                          ),
                          Semantics(
                            button: true,
                            label: playerState.isPlaying ? 'Pause' : 'Play',
                            child: GestureDetector(
                              onTap: () => playerState.isPlaying
                                  ? notifier.player.pause()
                                  : notifier.player.play(),
                              child: Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                  color: ThemeTokens.of(context).textPrimary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: ThemeTokens.of(
                                        context,
                                      ).textPrimary.withOpacity(0.22),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                        scale: anim,
                                        child: child,
                                      ),
                                  child: Icon(
                                    playerState.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey(playerState.isPlaying),
                                    size: 42,
                                    color: ThemeTokens.of(context).bgBase,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Skip Next',
                            icon: Icon(
                              Icons.skip_next_rounded,
                              size: 48,
                              color: ThemeTokens.of(context).textPrimary,
                            ),
                            onPressed: () => notifier.playNext(),
                          ),
                          IconButton(
                            tooltip: 'Cycle Repeat Mode',
                            icon: Icon(
                              playerState.repeatMode == LoopMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: isRepeatActive
                                  ? ThemeTokens.of(context).accent
                                  : ThemeTokens.of(context).textSecondary,
                              size: 26,
                            ),
                            onPressed: () => notifier.cycleRepeat(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _VolumeSlider(player: notifier.player),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _BottomAction(
                            icon: _SoundBar(
                              isPlaying: playerState.isPlaying,
                              color: ThemeTokens.of(context).textSecondary,
                            ),
                            label: playerState.isPlaying ? 'Playing' : 'Paused',
                            labelColor: ThemeTokens.of(context).textMuted,
                            onTap: () {},
                          ),
                          _BottomAction(
                            icon: Icon(
                              Icons.all_inclusive_rounded,
                              color: playerState.autoplayMode
                                  ? ThemeTokens.of(context).accent
                                  : ThemeTokens.of(context).textSecondary,
                              size: 24,
                            ),
                            label: 'Autoplay',
                            labelColor: playerState.autoplayMode
                                ? ThemeTokens.of(context).accent
                                : ThemeTokens.of(context).textSecondary,
                            onTap: () => notifier.toggleAutoplay(),
                          ),
                          ValueListenableBuilder<int?>(
                            valueListenable: _sleepSeconds,
                            builder: (_, remaining, __) => _BottomAction(
                              icon: Icon(
                                Icons.bedtime_outlined,
                                color: remaining != null
                                    ? ThemeTokens.of(context).accent
                                    : ThemeTokens.of(context).textSecondary,
                                size: 24,
                              ),
                              label: remaining != null
                                  ? _formatSleepLabel(remaining)
                                  : 'Sleep',
                              labelColor: remaining != null
                                  ? ThemeTokens.of(context).accent
                                  : ThemeTokens.of(context).textSecondary,
                              onTap: _showSleepTimerDialog,
                            ),
                          ),
                          _BottomAction(
                            icon: Icon(
                              Icons.queue_music_rounded,
                              color: ThemeTokens.of(context).textSecondary,
                              size: 24,
                            ),
                            label: 'Queue',
                            labelColor: ThemeTokens.of(context).textSecondary,
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const QueueScreen(),
                            ),
                          ),
                          _BottomAction(
                            icon: Icon(
                              Icons.lyrics_outlined,
                              color: ThemeTokens.of(context).textSecondary,
                              size: 24,
                            ),
                            label: 'Lyrics',
                            labelColor: ThemeTokens.of(context).textSecondary,
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => LyricsView(
                                song: song,
                                imageUrl: imageUrl,
                              ),
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
// 5b. POSITION STREAM — flash-free progress bar wrapper
// =============================================================================

/// Wraps [ProgressBar] and subscribes to [AudioPlayer.positionStream] in a
/// StatefulWidget so we can cache the last-known position.
///
/// **Why not `StreamBuilder`?** When `just_audio` switches sources it briefly
/// emits `null` on `positionStream`, which `StreamBuilder`'s
/// `snapshot.data ?? Duration.zero` maps to 0 — causing the progress bar to
/// visually reset to zero for a single frame (the flash bug).
///
/// This widget holds `_lastKnown` and only updates it when the incoming
/// position is `> Duration.zero` OR when the song has genuinely changed (in
/// which case we intentionally reset to zero once the first real position
/// arrives).
class _PositionStream extends StatefulWidget {
  final AudioPlayer player;
  final String songId;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _PositionStream({
    required this.player,
    required this.songId,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_PositionStream> createState() => _PositionStreamState();
}

class _PositionStreamState extends State<_PositionStream> {
  late StreamSubscription<Duration> _sub;
  Duration _lastKnown = Duration.zero;
  String _lastSongId = '';

  @override
  void initState() {
    super.initState();
    _lastSongId = widget.songId;
    _sub = widget.player.positionStream.listen(_onPosition);
  }

  void _onPosition(Duration pos) {
    if (!mounted) return;
    final songChanged = widget.songId != _lastSongId;
    if (songChanged) {
      // New song detected — reset cache so we start from 0 cleanly.
      setState(() {
        _lastKnown = Duration.zero;
        _lastSongId = widget.songId;
      });
      return;
    }
    // Only update if pos is meaningful — never overwrite a non-zero cache
    // with a transient zero emitted during source switching.
    if (pos > Duration.zero || _lastKnown == Duration.zero) {
      setState(() => _lastKnown = pos);
    }
  }

  @override
  void didUpdateWidget(_PositionStream old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      // Song changed from parent — reset immediately so the bar shows 0
      // until the player emits the first real position for the new track.
      _lastSongId = widget.songId;
      _lastKnown = Duration.zero;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProgressBar(
      position: _lastKnown,
      duration: widget.duration,
      onSeek: widget.onSeek,
    );
  }
}

// =============================================================================
// 6. QUEUE SCREEN
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
    final notifier = ref.read(playerProvider.notifier);
    // FIX BUG-6: Use typed SubsonicService instead of dynamic.
    final service = ref.read(subsonicServiceProvider);

    final upNext = playerState.upNext;
    final history = playerState.historySongs;
    final currentSong = playerState.currentSong;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeTokens.of(context).bgSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ThemeTokens.of(context).textMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Queue',
                          style: TextStyle(
                            color: ThemeTokens.of(context).textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        AnimatedBuilder(
                          animation: _tabs,
                          builder: (_, __) {
                            if (_tabs.index != 1 || history.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return TextButton(
                              onPressed: () => notifier.clearHistory(),
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: ThemeTokens.of(
                          context,
                        ).textPrimary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: TabBar(
                        controller: _tabs,
                        indicator: BoxDecoration(
                          color: ThemeTokens.of(
                            context,
                          ).textPrimary.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: ThemeTokens.of(context).textPrimary,
                        unselectedLabelColor: ThemeTokens.of(context).textMuted,
                        labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.queue_music_rounded, size: 14),
                                const SizedBox(width: 5),
                                Text('Up Next (${upNext.length})'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.history_rounded, size: 14),
                                const SizedBox(width: 5),
                                Text('History (${history.length})'),
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
              if (currentSong != null) ...[
                _NowPlayingStrip(song: currentSong, service: service),
                Divider(color: ThemeTokens.of(context).outline, height: 1),
              ],
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    upNext.isEmpty
                        ? const _EmptyTab(
                            icon: Icons.queue_music_rounded,
                            label: 'Nothing up next',
                          )
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: upNext.length,
                            onReorder: (oldIdx, newIdx) {
                              final qOld =
                                  playerState.currentIndex + 1 + oldIdx;
                              final qNew =
                                  playerState.currentIndex + 1 + newIdx;
                              notifier.reorderQueue(qOld, qNew);
                            },
                            itemBuilder: (context, i) {
                              final s = upNext[i];
                              final qIdx = playerState.currentIndex + 1 + i;
                              return _QueueTile(
                                key: ValueKey('nxt_${s.id}_$i'),
                                song: s,
                                service: service,
                                onTap: () {
                                  notifier.jumpTo(qIdx);
                                  Navigator.pop(context);
                                },
                                onRemove: () => notifier.removeFromQueue(qIdx),
                                dragHandle: ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: ThemeTokens.of(context).textMuted,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                    history.isEmpty
                        ? const _EmptyTab(
                            icon: Icons.history_rounded,
                            label: 'No songs played yet',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: history.length,
                            itemBuilder: (context, i) {
                              final song = history[history.length - 1 - i];
                              return _HistoryTile(
                                key: ValueKey('hist_${song.id}_$i'),
                                song: song,
                                service: service,
                                isNewest: i == 0,
                                onTap: () {
                                  final qIdx = playerState.queue.lastIndexWhere(
                                    (s) => s.id == song.id,
                                  );
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
// 7. QUEUE SCREEN SUB-WIDGETS
// =============================================================================

class _NowPlayingStrip extends StatelessWidget {
  final Song song;
  // FIX BUG-6: Use the concrete SubsonicService type instead of dynamic.
  final SubsonicService service;
  const _NowPlayingStrip({required this.song, required this.service});

  @override
  Widget build(BuildContext context) {
    final url = service.getCoverArtUrl(song.coverArt);
    final key = 'cover_${song.coverArt ?? song.id}';
    return Container(
      color: ThemeTokens.of(context).textPrimary.withOpacity(0.05),
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
                color: ThemeTokens.of(context).bgSurface,
                child: Icon(
                  Icons.music_note_rounded,
                  color: ThemeTokens.of(context).textMuted,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeTokens.of(context).textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeTokens.of(context).textSecondary,
                    fontSize: 12,
                  ),
                ),
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
    for (int i = 0; i < 3; i++) {
      _phases.add(_rng.nextDouble() * math.pi * 2);
    }
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
                  (math.sin(_ctrl.value * math.pi * 2 + _phases[i]) + 1) / 2;
              return Container(
                width: 2.5,
                height: (3 + t * 11).toDouble(),
                decoration: BoxDecoration(
                  color: ThemeTokens.of(context).accent,
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
  // FIX BUG-6: Typed service.
  final SubsonicService service;
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
    final url = service.getCoverArtUrl(song.coverArt);
    final key = 'cover_${song.coverArt ?? song.id}';
    return Dismissible(
      key: ValueKey('dis_q_${song.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.redAccent.withOpacity(0.80)],
          ),
        ),
        child: Icon(
          Icons.remove_circle_outline_rounded,
          color: ThemeTokens.of(context).textPrimary,
          size: 22,
        ),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              color: ThemeTokens.of(context).bgSurface,
              child: Icon(
                Icons.music_note_rounded,
                color: ThemeTokens.of(context).textMuted,
                size: 20,
              ),
            ),
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeTokens.of(context).textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeTokens.of(context).textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: dragHandle,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Song song;
  // FIX BUG-6: Typed service.
  final SubsonicService service;
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
    final url = service.getCoverArtUrl(song.coverArt);
    final key = 'cover_${song.coverArt ?? song.id}';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                color: ThemeTokens.of(context).bgSurface,
                child: Icon(
                  Icons.music_note_rounded,
                  color: ThemeTokens.of(context).textMuted,
                  size: 20,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).bgOverlay.withOpacity(0.65),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: ThemeTokens.of(context).textSecondary,
                size: 11,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isNewest
              ? ThemeTokens.of(context).textPrimary
              : ThemeTokens.of(context).textPrimary.withOpacity(0.72),
          fontSize: 14,
          fontWeight: isNewest ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isNewest
              ? ThemeTokens.of(context).textSecondary
              : ThemeTokens.of(context).textSecondary.withOpacity(0.7),
          fontSize: 12,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(
            Icons.history_rounded,
            color: ThemeTokens.of(context).textMuted.withOpacity(0.5),
            size: 15,
          ),
          if (isNewest)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Last played',
                style: TextStyle(
                  color: ThemeTokens.of(context).textMuted,
                  fontSize: 9,
                ),
              ),
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
          Icon(
            icon,
            color: ThemeTokens.of(context).textMuted.withOpacity(0.3),
            size: 54,
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              color: ThemeTokens.of(context).textMuted,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
