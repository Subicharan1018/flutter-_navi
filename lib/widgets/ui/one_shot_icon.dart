import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/motion.dart';

/// An illustrated icon that rests on its still frame and plays its animation
/// exactly once when [OneShotIconState.play] is called (e.g. on tap), then
/// settles back on the still. Assets come in pairs under `assets/icons/`:
/// `<name>.png` (resting frame) and `<name>.webp` (one-shot animation, whose
/// last frame matches the first).
class OneShotIcon extends StatefulWidget {
  final String name;
  final double size;

  /// Length of the animation; the still returns after it.
  final Duration duration;

  const OneShotIcon({super.key, required this.name, required this.size, required this.duration});

  @override
  State<OneShotIcon> createState() => OneShotIconState();
}

class OneShotIconState extends State<OneShotIcon> {
  bool _playing = false;
  Timer? _done;

  String get _still => 'assets/icons/${widget.name}.png';
  String get _animation => 'assets/icons/${widget.name}.webp';

  /// Plays the animation from its first frame, once. Ignored when the system
  /// asks for reduced motion.
  void play() {
    if (!context.motionFullNow) return;
    // A fresh decode always starts at frame 0 (the cached stream would resume
    // wherever it stopped, or not play at all after finishing).
    _provider(_animation).evict();
    _done?.cancel();
    setState(() => _playing = true);
    _done = Timer(widget.duration, () {
      if (mounted) setState(() => _playing = false);
    });
  }

  ImageProvider _provider(String asset) {
    final px = (widget.size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3)).round();
    return ResizeImage(AssetImage(asset), width: px, height: px);
  }

  @override
  void dispose() {
    _done?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = Image(image: _provider(_still), width: widget.size, height: widget.size, gaplessPlayback: true);
    if (!_playing) return still;
    return Image(
      image: _provider(_animation),
      width: widget.size,
      height: widget.size,
      gaplessPlayback: true,
      // Keep the still on screen until the first animated frame decodes.
      frameBuilder: (context, child, frame, _) => frame == null ? still : child,
    );
  }
}
