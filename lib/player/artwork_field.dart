import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/album_palette.dart';
import 'artwork.dart';

/// The living background of Now Playing: the cover's own pixels flowing
/// slowly behind the controls.
///
/// Cost control:
///  * the shader renders into an offscreen target at 1/[_downscale] of the
///    widget size and is upscaled with bilinear filtering — the field is soft
///    by design, so this is invisible and ~36× cheaper than full resolution;
///  * drift advances only while [playing], capped at 30 fps, and stops when
///    the route is covered (TickerMode) or the OS asks to reduce motion;
///  * song changes cross-fade between the two cover textures in the shader.
class ArtworkField extends StatefulWidget {
  final ArtworkData? art;
  final bool playing;

  /// 0..1 extra darkening for dense content (lyrics, queue).
  final double dim;

  const ArtworkField({super.key, required this.art, required this.playing, this.dim = 0});

  static Future<ui.FragmentProgram>? _program;

  /// Load and compile the shader ahead of first use (called from main).
  static Future<void> precache() async {
    try {
      await (_program ??= ui.FragmentProgram.fromAsset('shaders/artwork_field.frag'));
    } catch (_) {
      // Falls back to the static field at runtime.
    }
  }

  @override
  State<ArtworkField> createState() => _ArtworkFieldState();
}

class _ArtworkFieldState extends State<ArtworkField> with TickerProviderStateMixin {
  static Future<ui.FragmentProgram>? get _program => ArtworkField._program;
  static const double _downscale = 6;

  ui.FragmentShader? _shader;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _mix = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  late final AnimationController _dim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.dim,
  );
  final ValueNotifier<double> _time = ValueNotifier(0);

  ArtworkData? _from; // outgoing
  ArtworkData? _to; // current
  Duration _lastElapsed = Duration.zero;
  double _sinceFrame = 0;

  @override
  void initState() {
    super.initState();
    _to = widget.art;
    _from = widget.art;
    ArtworkField._program ??= ui.FragmentProgram.fromAsset('shaders/artwork_field.frag');
    _program!.then((p) {
      if (mounted) setState(() => _shader = p.fragmentShader());
    }).catchError((Object e) {
      debugPrint('[ArtworkField] shader unavailable, using static field: $e');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(ArtworkField old) {
    super.didUpdateWidget(old);
    if (widget.art?.key != _to?.key && widget.art != null) {
      _from = _to ?? widget.art;
      _to = widget.art;
      _mix.forward(from: 0);
    }
    if (widget.dim != old.dim) {
      _dim.animateTo(widget.dim, curve: Curves.easeOutCubic);
    }
    _syncTicker();
  }

  void _syncTicker() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = widget.playing && !reduce;
    if (run && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _sinceFrame += dt;
    if (_sinceFrame < 1 / 30) return; // 30 fps is plenty for slow drift
    _time.value += _sinceFrame;
    _sinceFrame = 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _mix.dispose();
    _dim.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _to?.palette ?? AlbumPalette.fallback;
    final shader = _shader;
    final from = _from, to = _to;
    if (shader == null || from == null || to == null) {
      return _StaticField(palette: palette);
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FieldPainter(
          shader: shader,
          from: from.image,
          to: to.image,
          deep: palette.deep,
          time: _time,
          mix: _mix,
          dim: _dim,
          downscale: _downscale,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image from;
  final ui.Image to;
  final Color deep;
  final ValueListenable<double> time;
  final Animation<double> mix;
  final Animation<double> dim;
  final double downscale;

  _FieldPainter({
    required this.shader,
    required this.from,
    required this.to,
    required this.deep,
    required this.time,
    required this.mix,
    required this.dim,
    required this.downscale,
  }) : super(repaint: Listenable.merge([time, mix, dim]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = (size.width / downscale).ceilToDouble().clamp(16.0, 512.0);
    final h = (size.height / downscale).ceilToDouble().clamp(16.0, 512.0);

    int i = 0;
    shader
      ..setFloat(i++, w)
      ..setFloat(i++, h)
      ..setFloat(i++, time.value)
      ..setFloat(i++, Curves.easeInOut.transform(mix.value))
      ..setFloat(i++, deep.r)
      ..setFloat(i++, deep.g)
      ..setFloat(i++, deep.b)
      ..setFloat(i++, 1)
      ..setFloat(i++, dim.value)
      // Linear filtering: the default (none) samples the 64px cover
      // nearest-neighbour and the field turns into visible blocks.
      ..setImageSampler(0, from, filterQuality: FilterQuality.medium)
      ..setImageSampler(1, to, filterQuality: FilterQuality.medium);

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
    final picture = recorder.endRecording();
    final frame = picture.toImageSync(w.toInt(), h.toInt());
    picture.dispose();

    canvas.drawImageRect(
      frame,
      Rect.fromLTWH(0, 0, w, h),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    frame.dispose();
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.from != from || old.to != to || old.deep != deep || old.shader != shader;
}

/// Shown until the shader and the first cover are ready (and on platforms
/// without runtime-effect support): the palette's own gradient, never black.
class _StaticField extends StatelessWidget {
  final AlbumPalette palette;
  const _StaticField({required this.palette});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.base, palette.glow, 0.25)!,
            palette.base,
            palette.deep,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}
