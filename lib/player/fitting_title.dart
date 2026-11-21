import 'dart:async';

import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// A one-line title that always reads.
///
/// It rests as a clean ellipsis (never cut mid-letter), so a screenshot or a
/// glance shows a finished-looking title. When it doesn't fit, it scrolls
/// across twice, after a beat, then settles back to the ellipsis: not a loop
/// that keeps the screen redrawing for as long as the song plays. Reduced
/// motion never scrolls; the long-press/open-details routes show the full text.
class FittingTitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  const FittingTitle({super.key, required this.text, required this.style});

  /// Beat before it scrolls, scroll speed (dp/s), the gap between the end and
  /// the repeat, and how many passes.
  static const Duration beat = Duration(milliseconds: 1800);
  static const double velocity = 36;
  static const double blank = 48;
  static const Duration restBetween = Duration(milliseconds: 900);
  static const int rounds = 2;

  @override
  State<FittingTitle> createState() => _FittingTitleState();
}

class _FittingTitleState extends State<FittingTitle> {
  bool _scrolling = false;
  Timer? _timer;
  String _armedFor = '';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Arms the start (and later the stop) once per title.
  void _arm(double textWidth) {
    if (_armedFor == widget.text) return;
    _armedFor = widget.text;
    _timer?.cancel();
    _scrolling = false;
    final pass = Duration(milliseconds: ((textWidth + FittingTitle.blank) / FittingTitle.velocity * 1000).round());
    _timer = Timer(FittingTitle.beat, () {
      if (!mounted) return;
      setState(() => _scrolling = true);
      _timer = Timer((pass + FittingTitle.restBetween) * FittingTitle.rounds, () {
        if (mounted) setState(() => _scrolling = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = tp.width;
      tp.dispose();
      final overflows = width > c.maxWidth;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final rest = Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
      if (!overflows || reduce) {
        _armedFor = '';
        return rest;
      }
      if (_armedFor != widget.text) {
        // Never setState during build: _arm only sets fields and a timer.
        _arm(width);
      }
      if (!_scrolling) return rest;
      return Marquee(
        key: ValueKey('scroll-${widget.text}'),
        text: widget.text,
        style: style,
        blankSpace: FittingTitle.blank,
        velocity: FittingTitle.velocity,
        startAfter: Duration.zero,
        pauseAfterRound: FittingTitle.restBetween,
        numberOfRounds: FittingTitle.rounds,
        fadingEdgeStartFraction: 0.04,
        fadingEdgeEndFraction: 0.1,
        showFadingOnlyWhenScrolling: true,
      );
    });
  }
}
