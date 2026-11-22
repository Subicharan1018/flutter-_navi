import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../lyrics/models/lyric_line.dart';

/// Whether a silence is long enough to be marked with dots rather than a gap.
bool isInstrumentalGap(Duration from, Duration to) => to - from >= const Duration(seconds: 4);

/// When a line has probably finished being sung: its last word plus a moment,
/// or a few seconds after its start when it has no word timing.
Duration sungUntil(LyricLine line) {
  final words = line.words;
  final guess = words != null && words.isNotEmpty
      ? words.last.timestamp + const Duration(milliseconds: 1400)
      : line.timestamp + const Duration(seconds: 6);
  return guess;
}

/// How many of the three dots are filled at [positionMs] in a gap that runs
/// from [startMs] to [endMs]: 0.0 to 3.0, each dot filling in turn.
double gapFill(int startMs, int endMs, int positionMs) {
  if (endMs <= startMs) return 3;
  return (3 * (positionMs - startMs) / (endMs - startMs)).clamp(0.0, 3.0);
}

/// Three dots for an instrumental break or intro, as in Apple Music: they fill
/// one after another across the gap, breathe gently, and fade away when the
/// singing starts.
///
/// The slot always keeps the same height, so the lines around it never shift
/// when the dots appear or leave. The ticker runs only while [active].
class LyricGapDots extends StatefulWidget {
  final bool active;
  final int startMs;
  final int endMs;
  final int Function() positionMs;
  final double size;
  final Color color;

  const LyricGapDots({
    super.key,
    required this.active,
    required this.startMs,
    required this.endMs,
    required this.positionMs,
    required this.size,
    required this.color,
  });

  @override
  State<LyricGapDots> createState() => _LyricGapDotsState();
}

class _LyricGapDotsState extends State<LyricGapDots> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final ValueNotifier<int> _pos = ValueNotifier(widget.positionMs());

  /// Shown once the song is inside the gap, not while the line before it is
  /// still being sung.
  late bool _inGap = widget.active && _pos.value >= widget.startMs;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final ms = widget.positionMs();
      if (ms != _pos.value) _pos.value = ms;
      final inGap = widget.active && ms >= widget.startMs;
      if (inGap != _inGap) setState(() => _inGap = inGap);
    });
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(LyricGapDots old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ticker.isActive) {
      _pos.value = widget.positionMs();
      _ticker.start();
    }
    if (!widget.active && _inGap) _inGap = false; // fade out
    // The ticker keeps running through the fade-out so the dots do not freeze
    // mid-breath, then stops (see [_onFaded]).
  }

  void _onFaded() {
    if (!widget.active && !_inGap && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final d = widget.size * 0.32;
    return SizedBox(
      height: widget.size * 1.5,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _inGap ? 1.0 : 0.0),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          onEnd: _onFaded,
          builder: (context, shown, child) => Opacity(
            opacity: shown,
            child: Transform.scale(scale: 0.6 + 0.4 * shown, alignment: Alignment.centerLeft, child: child),
          ),
          child: RepaintBoundary(
            child: ValueListenableBuilder<int>(
              valueListenable: _pos,
              builder: (context, ms, _) {
                final fill = gapFill(widget.startMs, widget.endMs, ms);
                final breathe = reduce ? 1.0 : 1 + 0.12 * math.sin(2 * math.pi * ms / 1800);
                return Transform.scale(
                  scale: breathe,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: d,
                          height: d,
                          margin: EdgeInsets.only(right: d * 0.6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.color.withValues(alpha: 0.3 + 0.6 * (fill - i).clamp(0.0, 1.0)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
