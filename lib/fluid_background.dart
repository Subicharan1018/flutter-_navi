import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── Shader loader ─────────────────────────────────────────────────────────────

/// @see [FluidBackground]
/// @dependency shader loading utility for the background community.
class FluidShaderLoader {
  FluidShaderLoader._();
  static final FluidShaderLoader instance = FluidShaderLoader._();

  ui.FragmentProgram? _program;
  Future<ui.FragmentProgram>? _future;

  Future<ui.FragmentProgram> load() {
    _future ??= ui.FragmentProgram.fromAsset('shaders/fluid_background.frag')
        .then((p) {
          _program = p;
          return p;
        });
    return _future!;
  }

  ui.FragmentProgram? get program => _program;
}

// ── Custom painter ────────────────────────────────────────────────────────────

/// @see [FluidBackground]
/// @dependency rendering utility for the background community.
class _FluidPainter extends CustomPainter {
  // FIX BUG-7: The shader instance is passed in from state and reused across
  // frames. Creating a new FragmentShader every build causes GPU resource
  // churn — the program is compiled once, but each shader() call allocates
  // a new uniform buffer on the GPU.
  final ui.FragmentShader shader;
  final double time;
  final List<Color> colors;
  final List<Color> prevColors;
  final double tColor;

  _FluidPainter({
    required this.shader,
    required this.time,
    required this.colors,
    required this.prevColors,
    required this.tColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform layout — must match fluid_background.frag exactly.
    //
    // FIX BUG-8: Flutter's runtime_effect.glsl does NOT support array
    // uniforms (uniform vec4 u_colors[4]). Each element must be a separate
    // uniform. The frag file must be updated to match this flat layout:
    //
    //   0  u_resolution.x
    //   1  u_resolution.y
    //   2  u_time
    //   3..6   u_color0  (rgba floats)
    //   7..10  u_color1
    //   11..14 u_color2
    //   15..18 u_color3
    //   19..22 u_colorPrev0
    //   23..26 u_colorPrev1
    //   27..30 u_colorPrev2
    //   31..34 u_colorPrev3
    //   35 u_tColor

    int idx = 0;

    shader.setFloat(idx++, size.width);
    shader.setFloat(idx++, size.height);
    shader.setFloat(idx++, time % 1000.0);

    for (int i = 0; i < 4; i++) {
      final c = i < colors.length ? colors[i] : const Color(0xFF1A1A2E);
      shader.setFloat(idx++, c.r);
      shader.setFloat(idx++, c.g);
      shader.setFloat(idx++, c.b);
      shader.setFloat(idx++, c.a);
    }

    for (int i = 0; i < 4; i++) {
      final c = i < prevColors.length ? prevColors[i] : const Color(0xFF1A1A2E);
      shader.setFloat(idx++, c.r);
      shader.setFloat(idx++, c.g);
      shader.setFloat(idx++, c.b);
      shader.setFloat(idx++, c.a);
    }

    shader.setFloat(idx++, tColor);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_FluidPainter old) =>
      old.time != time ||
      old.tColor != tColor ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.prevColors, prevColors);
}

// ── Animated widget ───────────────────────────────────────────────────────────

/// An animated fluid background widget.
///
/// This widget delegates to [_FluidPainter] for the actual rendering and uses
/// [FluidShaderLoader] to load the underlying fragment shader.
class FluidBackground extends StatefulWidget {
  final List<Color> colors;

  /// When false, the steady-state fluid animation freezes (no repaints), cutting
  /// the continuous ~30fps GPU cost to near-zero while playback is paused.
  /// In-progress colour fades still complete (album-art changes transition even
  /// when paused). Defaults to true so callers that don't care keep animating.
  final bool isPlaying;

  const FluidBackground({
    super.key,
    required this.colors,
    this.isPlaying = true,
  });

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsed = 0;
  double _lastTickElapsed = 0;

  List<Color> _currentColors = const [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
  ];
  List<Color> _prevColors = const [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
  ];

  double _tColor = 1.0;
  static const double _kFadeDuration = 1.5;
  double _fadeStartElapsed = 0;
  bool _fading = false;
  double _lastRepaintElapsed = 0;

  ui.FragmentProgram? _program;

  // FIX BUG-7: One shader instance, allocated once when the program is ready
  // and reused every frame. Destroyed in dispose().
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _currentColors = List.of(widget.colors);
    _prevColors = List.of(widget.colors);

    _ticker = createTicker(_onTick);
    _syncTicker();

    _program = FluidShaderLoader.instance.program;
    if (_program != null) {
      _shader = _program!.fragmentShader();
    } else {
      FluidShaderLoader.instance.load().then((p) {
        if (mounted) {
          setState(() {
            _program = p;
            _shader = p.fragmentShader();
          });
        }
      });
    }
  }

  void _syncTicker() {
    final shouldTick = widget.isPlaying || _fading;
    if (shouldTick && !_ticker.isActive) {
      _lastTickElapsed = 0.0;
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(FluidBackground old) {
    super.didUpdateWidget(old);
    if (!listEquals(widget.colors, old.colors)) {
      _prevColors = _lerpedColors;
      _currentColors = List.of(widget.colors);
      _fadeStartElapsed = _elapsed;
      _fading = true;
      _tColor = 0.0;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    // FIX BUG-7: Release the GPU uniform buffer when the widget is destroyed.
    _shader?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    
    final currentElapsed = elapsed.inMicroseconds / 1e6;
    final delta = _lastTickElapsed == 0.0 ? 0.0 : (currentElapsed - _lastTickElapsed);
    _lastTickElapsed = currentElapsed;

    _elapsed += delta;

    if (_fading) {
      final progress = (_elapsed - _fadeStartElapsed) / _kFadeDuration;
      if (progress >= 1.0) {
        _tColor = 1.0;
        _fading = false;
        _syncTicker();
      } else {
        final t = progress < 0.5
            ? 4 * progress * progress * progress
            : 1 -
                  (-2 * progress + 2) *
                      (-2 * progress + 2) *
                      (-2 * progress + 2) /
                      2;
        _tColor = t.clamp(0.0, 1.0);
      }
      // Color fade needs full-rate updates for smooth transition.
      setState(() {});
      _lastRepaintElapsed = _elapsed;
      return;
    }

    // Freeze the steady-state animation while paused — no repaints, near-zero
    // GPU/thermal. The _fading branch above still ran (and returned), so colour
    // transitions finish even when paused. Animation resumes the moment
    // isPlaying flips back to true (the ticker is never stopped).
    if (!widget.isPlaying) return;

    // Background fluid animation: cap to ~30fps to halve GPU cost.
    // Animated backgrounds don't need 60fps — the difference is imperceptible.
    if (_elapsed - _lastRepaintElapsed >= 1 / 30) {
      _lastRepaintElapsed = _elapsed;
      setState(() {});
    }
  }

  List<Color> get _lerpedColors => List.generate(
    _currentColors.length,
    (i) => Color.lerp(_prevColors[i], _currentColors[i], _tColor)!,
  );

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return AppleMusicFluidMesh(
        colors: _currentColors,
        prevColors: _prevColors,
        tColor: _tColor,
        isPlaying: widget.isPlaying,
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _FluidPainter(
          shader: _shader!,
          time: _elapsed,
          colors: _currentColors,
          prevColors: _prevColors,
          tColor: _tColor,
        ),
        size: Size.infinite,
        isComplex: true,
        willChange: true,
      ),
    );
  }
}

// ── Apple Music Animated Fluid Mesh (Canvas/Orbs Engine) ──────────────────────

class AppleMusicFluidMesh extends StatefulWidget {
  final List<Color> colors;
  final List<Color>? prevColors;
  final double tColor;
  final bool isPlaying;

  const AppleMusicFluidMesh({
    super.key,
    required this.colors,
    this.prevColors,
    this.tColor = 1.0,
    this.isPlaying = true,
  });

  @override
  State<AppleMusicFluidMesh> createState() => _AppleMusicFluidMeshState();
}

class _AppleMusicFluidMeshState extends State<AppleMusicFluidMesh>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void didUpdateWidget(AppleMusicFluidMesh old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c0 = widget.colors.isNotEmpty ? widget.colors[0] : const Color(0xFFE50914);
    final c1 = widget.colors.length > 1 ? widget.colors[1] : const Color(0xFF8B5CF6);
    final c2 = widget.colors.length > 2 ? widget.colors[2] : const Color(0xFF06B6D4);
    final c3 = widget.colors.length > 3 ? widget.colors[3] : const Color(0xFFEC4899);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * 3.1415926535;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Deep vibrant base
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(c0, Colors.black, 0.45)!,
                    Color.lerp(c2, Colors.black, 0.60)!,
                  ],
                ),
              ),
            ),

            // Flowing Body 1 (Top Left / Center)
            Positioned(
              left: -150 + 200 * (0.5 + 0.5 * mathSin(t * 1.1 + 0.4)),
              top: -150 + 180 * (0.5 + 0.5 * mathCos(t * 0.8)),
              width: 850,
              height: 850,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c0.withValues(alpha: 0.85),
                      c0.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Flowing Body 2 (Top Right / Center)
            Positioned(
              right: -180 + 220 * (0.5 + 0.5 * mathCos(t * 0.9 + 1.2)),
              top: -100 + 200 * (0.5 + 0.5 * mathSin(t * 1.3 + 0.9)),
              width: 900,
              height: 900,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c1.withValues(alpha: 0.80),
                      c1.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.60, 1.0],
                  ),
                ),
              ),
            ),

            // Flowing Body 3 (Bottom Left / Center)
            Positioned(
              left: -120 + 250 * (0.5 + 0.5 * mathSin(t * 0.7 + 2.4)),
              bottom: -180 + 180 * (0.5 + 0.5 * mathCos(t * 1.2 + 1.7)),
              width: 950,
              height: 950,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c2.withValues(alpha: 0.75),
                      c2.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Flowing Body 4 (Bottom Right / Center)
            Positioned(
              right: -150 + 200 * (0.5 + 0.5 * mathCos(t * 1.4 + 3.1)),
              bottom: -150 + 220 * (0.5 + 0.5 * mathSin(t * 0.8 + 2.1)),
              width: 880,
              height: 880,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c3.withValues(alpha: 0.80),
                      c3.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Frosted Glass Gaussian Blur Layer
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 75, sigmaY: 75),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double mathSin(double v) => (v != 0) ? (v.abs() % (2 * 3.14159) == 0 ? 0.0 : _sin(v)) : 0.0;
  double mathCos(double v) => (v != 0) ? _cos(v) : 1.0;

  double _sin(double v) {
    // Fast Taylor / standard sin via math
    return (v < -3.14159 || v > 3.14159)
        ? (v % (2 * 3.14159) - 3.14159).abs() - 1.57079
        : (v - v * v * v / 6.0 + v * v * v * v * v / 120.0).clamp(-1.0, 1.0);
  }

  double _cos(double v) => _sin(v + 1.57079632679);
}

// =============================================================================
// Apple Music Live Background (Windows & Desktop Dedicated Experience)
// =============================================================================

/// Living, continuous moving background modeled directly on Apple Music for Windows/macOS.
///
/// Features:
/// 1. Scaled, moving cover art texture (upscaled ~3x, dynamic Lissajous drift, gentle breathing scale).
/// 2. Heavy dual-pass Gaussian blur (sigma 85) creating an exact color-and-lighting atmospheric field.
/// 3. Luminous organic fluid color orbs overlaying the image to add liquid motion.
/// 4. Delicate dark vignette for perfect contrast against foreground lyrics and controls.
class AppleMusicLiveBackground extends StatefulWidget {
  final String imageUrl;
  final List<Color> colors;
  final bool isPlaying;

  const AppleMusicLiveBackground({
    super.key,
    required this.imageUrl,
    required this.colors,
    this.isPlaying = true,
  });

  @override
  State<AppleMusicLiveBackground> createState() => _AppleMusicLiveBackgroundState();
}

class _AppleMusicLiveBackgroundState extends State<AppleMusicLiveBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppleMusicLiveBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_controller.isAnimating) _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2.0 * math.pi;

        // Phase 1 transforms (Primary cover drift)
        final dx1 = 65.0 * math.sin(t * 0.6);
        final dy1 = 45.0 * math.cos(t * 0.45);
        final scale1 = 2.90 + 0.35 * math.sin(t * 0.35);
        final rot1 = 0.05 * math.sin(t * 0.3);

        // Phase 2 transforms (Harmonic counter-flow)
        final dx2 = -55.0 * math.cos(t * 0.55);
        final dy2 = 50.0 * math.sin(t * 0.7);
        final scale2 = 3.30 + 0.40 * math.cos(t * 0.4);
        final rot2 = -0.04 * math.cos(t * 0.25);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Deep base fallback color
            Container(color: const Color(0xFF060606)),

            if (widget.imageUrl.isNotEmpty) ...[
              // Heavy Gaussian Blur Container for all moving image layers
              Positioned.fill(
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 95,
                      sigmaY: 95,
                      tileMode: TileMode.clamp,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Layer 1: Primary flowing cover texture
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(scale1, scale1, 1.0)
                            ..setTranslationRaw(dx1, dy1, 0.0)
                            ..rotateZ(rot1),
                          child: CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 640,
                            memCacheHeight: 640,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),

                        // Layer 2: Counter-phase fluid layer for dynamic liquid motion
                        Opacity(
                          opacity: 0.55,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(scale2, scale2, 1.0)
                              ..setTranslationRaw(dx2, dy2, 0.0)
                              ..rotateZ(rot2),
                            child: CachedNetworkImage(
                              imageUrl: widget.imageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 640,
                              memCacheHeight: 640,
                              errorWidget: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Layer 3: Delicate cinematic vignette for pure foreground text contrast
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, 0.0),
                    radius: 1.35,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.60),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
