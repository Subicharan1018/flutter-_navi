import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

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
      shader.setFloat(idx++, c.red / 255.0);
      shader.setFloat(idx++, c.green / 255.0);
      shader.setFloat(idx++, c.blue / 255.0);
      shader.setFloat(idx++, c.alpha / 255.0);
    }

    for (int i = 0; i < 4; i++) {
      final c = i < prevColors.length ? prevColors[i] : const Color(0xFF1A1A2E);
      shader.setFloat(idx++, c.red / 255.0);
      shader.setFloat(idx++, c.green / 255.0);
      shader.setFloat(idx++, c.blue / 255.0);
      shader.setFloat(idx++, c.alpha / 255.0);
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
  const FluidBackground({super.key, required this.colors});

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsed = 0;

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

    _ticker = createTicker(_onTick)..start();

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
    _elapsed = elapsed.inMicroseconds / 1e6;

    if (_fading) {
      final progress = (_elapsed - _fadeStartElapsed) / _kFadeDuration;
      if (progress >= 1.0) {
        _tColor = 1.0;
        _fading = false;
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

    return RepaintBoundary(
      child: CustomPaint(
        // FIX BUG-7: Pass the cached _shader — not _program!.fragmentShader()
        // which would allocate a new GPU buffer on every build call.
        painter: _FluidPainter(
          shader: _shader!,
          time: _elapsed,
          colors: _currentColors,
          prevColors: _prevColors,
          tColor: _tColor,
        ),
        size: Size.infinite,
        isComplex: false,
        willChange: true,
      ),
    );
  }
}
