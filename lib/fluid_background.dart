// =============================================================================
// fluid_background.dart
//
// Drop-in replacement for _AnimatedBackground / _AppleMusicPainter.
//
// Key differences vs. the old saveLayer approach
// ───────────────────────────────────────────────
//  OLD                               NEW
//  ───────────────────────────────── ──────────────────────────────────
//  Canvas.saveLayer + ImageFilter    FragmentShader (GPU only)
//  Full-screen offscreen buffer      No extra VRAM allocation
//  5 × RadialGradient on CPU         5 blobs computed per-pixel on GPU
//  σ=40 Gaussian convolution         FBM domain-warp (one texture tap)
//  ~3 ms CPU + heavy GPU kernel      ~0.05 ms CPU, cheap GPU fragment
//
// Usage – exact same API as the old _AnimatedBackground:
//
//   FluidBackground(colors: _blobColors)   // replaces _AnimatedBackground
//
// pubspec.yaml must declare the shader:
//
//   flutter:
//     shaders:
//       - shaders/fluid_background.frag
// =============================================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ── Shader loader ─────────────────────────────────────────────────────────────

/// Singleton that loads the fragment program once and caches it.
/// Call [FluidShaderLoader.instance.load()] once at app start
/// (e.g. in main() after WidgetsFlutterBinding.ensureInitialized()).
class FluidShaderLoader {
  FluidShaderLoader._();
  static final FluidShaderLoader instance = FluidShaderLoader._();

  ui.FragmentProgram? _program;
  Future<ui.FragmentProgram>? _future;

  /// Returns a [Future] that resolves to the compiled [FragmentProgram].
  /// Safe to call multiple times – compilation happens only once.
  Future<ui.FragmentProgram> load() {
    _future ??= ui.FragmentProgram.fromAsset('shaders/fluid_background.frag')
        .then((p) { _program = p; return p; });
    return _future!;
  }

  /// Synchronous accessor – null until [load()] has resolved.
  ui.FragmentProgram? get program => _program;
}

// ── Custom painter ────────────────────────────────────────────────────────────

class _FluidPainter extends CustomPainter {
  final ui.FragmentShader shader;

  /// Monotonic seconds, wraps at 1 000 to stay inside float precision.
  final double time;

  /// Four jewel-tone colours extracted from the album artwork.
  final List<Color> colors;

  /// Previous album palette (cross-fade source).
  final List<Color> prevColors;

  /// Cross-fade progress 0 → previous palette, 1 → current palette.
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
    // ── Set uniforms ──────────────────────────────────────────────────────────
    //
    // Uniform layout (must match fluid_background.frag exactly):
    //
    //   0  u_resolution.x   float
    //   1  u_resolution.y   float
    //   2  u_time           float
    //   3  u_colors[0].r    float  \
    //   4  u_colors[0].g    float   |  4 colours × 4 components = 16 floats
    //   5  u_colors[0].b    float   |
    //   6  u_colors[0].a    float  /
    //   … (indices 7-18 for colors[1..3])
    //   19 u_colorsPrev[0].r …      16 floats (indices 19-34)
    //   35 u_tColor          float

    int idx = 0;

    // u_resolution
    shader.setFloat(idx++, size.width);
    shader.setFloat(idx++, size.height);

    // u_time
    shader.setFloat(idx++, time % 1000.0);

    // u_colors[0..3]
    for (int i = 0; i < 4; i++) {
      final c = i < colors.length ? colors[i] : const Color(0xFF1A1A2E);
      shader.setFloat(idx++, c.red   / 255.0);
      shader.setFloat(idx++, c.green / 255.0);
      shader.setFloat(idx++, c.blue  / 255.0);
      shader.setFloat(idx++, c.alpha / 255.0);
    }

    // u_colorsPrev[0..3]
    for (int i = 0; i < 4; i++) {
      final c = i < prevColors.length ? prevColors[i] : const Color(0xFF1A1A2E);
      shader.setFloat(idx++, c.red   / 255.0);
      shader.setFloat(idx++, c.green / 255.0);
      shader.setFloat(idx++, c.blue  / 255.0);
      shader.setFloat(idx++, c.alpha / 255.0);
    }

    // u_tColor
    shader.setFloat(idx++, tColor);

    // ── Draw full-screen rect with the shader ─────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_FluidPainter old) =>
      old.time != time ||
      old.tColor != tColor ||
      old.colors != colors ||
      old.prevColors != prevColors;
}

// ── Animated widget ───────────────────────────────────────────────────────────

/// Drop-in replacement for the old `_AnimatedBackground` widget.
///
/// Renders the fluid Apple Music background via a GPU fragment shader.
/// Falls back to a simple dark gradient while the shader is loading
/// (typically < 1 frame on a warm AssetBundle cache).
class FluidBackground extends StatefulWidget {
  /// Four jewel-tone colours extracted from the current album artwork.
  /// Must have exactly 4 elements; supply fallbacks if fewer are available.
  final List<Color> colors;

  const FluidBackground({super.key, required this.colors});

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with SingleTickerProviderStateMixin {
  // ── Ticker: drives u_time ─────────────────────────────────────────────────
  late final Ticker _ticker;
  double _elapsed = 0;   // seconds

  // ── Cross-fade state ──────────────────────────────────────────────────────
  List<Color> _currentColors = const [
    Color(0xFF1A1A2E), Color(0xFF16213E),
    Color(0xFF0F3460), Color(0xFF533483),
  ];
  List<Color> _prevColors = const [
    Color(0xFF1A1A2E), Color(0xFF16213E),
    Color(0xFF0F3460), Color(0xFF533483),
  ];

  // t=0 means show _prevColors, t=1 means show _currentColors
  double _tColor = 1.0;

  // Simple manual lerp: runs for _kFadeDuration seconds
  static const double _kFadeDuration = 1.5; // seconds
  double _fadeStartElapsed = 0;
  bool   _fading = false;

  // ── Shader ────────────────────────────────────────────────────────────────
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _currentColors = List.of(widget.colors);
    _prevColors    = List.of(widget.colors);

    _ticker = createTicker(_onTick)..start();

    // If the shader is already compiled (warm cache), use it immediately.
    // Otherwise kick off the load and rebuild when it resolves.
    _program = FluidShaderLoader.instance.program;
    if (_program == null) {
      FluidShaderLoader.instance.load().then((p) {
        if (mounted) setState(() => _program = p);
      });
    }
  }

  @override
  void didUpdateWidget(FluidBackground old) {
    super.didUpdateWidget(old);
    if (widget.colors != old.colors) {
      // Start a colour cross-fade
      _prevColors       = _lerpedColors;  // snapshot mid-fade colours
      _currentColors    = List.of(widget.colors);
      _fadeStartElapsed = _elapsed;
      _fading           = true;
      _tColor           = 0.0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    _elapsed = elapsed.inMicroseconds / 1e6;

    if (_fading) {
      final progress = (_elapsed - _fadeStartElapsed) / _kFadeDuration;
      if (progress >= 1.0) {
        _tColor = 1.0;
        _fading = false;
      } else {
        // ease-in-out cubic
        final t = progress < 0.5
            ? 4 * progress * progress * progress
            : 1 - (-2 * progress + 2) * (-2 * progress + 2) * (-2 * progress + 2) / 2;
        _tColor = t.clamp(0.0, 1.0);
      }
    }

    setState(() {}); // rebuild each frame (CustomPaint will skip if unchanged)
  }

  /// Returns the colours as they look right now (mid-fade interpolation).
  List<Color> get _lerpedColors => List.generate(
    _currentColors.length,
    (i) => Color.lerp(_prevColors[i], _currentColors[i], _tColor)!,
  );

  @override
  Widget build(BuildContext context) {
    // ── Fallback while shader is loading ──────────────────────────────────────
    if (_program == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(_currentColors[0], Colors.black, 0.65)!,
              Colors.black,
            ],
          ),
        ),
      );
    }

    // ── Shader path ───────────────────────────────────────────────────────────
    final shader = _program!.fragmentShader();

    return RepaintBoundary(
      child: CustomPaint(
        painter: _FluidPainter(
          shader:     shader,
          time:       _elapsed,
          colors:     _currentColors,
          prevColors: _prevColors,
          tColor:     _tColor,
        ),
        size: Size.infinite,
        isComplex: false,   // shader is cheap; skip raster-cache hint
        willChange: true,
      ),
    );
  }
}
