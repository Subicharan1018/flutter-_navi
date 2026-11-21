import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../lyrics/models/lyric_line.dart';

/// How far into word [i] the song is, 0 (not started) to 1 (sung).
///
/// A word lasts until the next one starts, but never longer than 1.4 s, so a
/// pause or an instrumental break doesn't leave a word glowing on and on.
double wordProgress(List<WordSegment> words, int i, Duration lineEnd, int positionMs) {
  final start = words[i].timestamp.inMilliseconds;
  var end = i + 1 < words.length ? words[i + 1].timestamp.inMilliseconds : lineEnd.inMilliseconds;
  end = math.min(end, start + 1400);
  if (end <= start) return positionMs >= start ? 1 : 0;
  return ((positionMs - start) / (end - start)).clamp(0.0, 1.0);
}

/// The sung line with each word filling in as it is sung.
///
/// Built only for the active line. Every frame (while the song moves) it
/// changes the colour of this one paragraph and nothing else: the text itself
/// never changes, so it is a repaint, not a relayout, and the rest of the list
/// stays still. With reduced motion a word switches on when it starts instead
/// of filling.
class LyricWordSweep extends StatefulWidget {
  final LyricLine line;

  /// When the line ends (the next line's start).
  final Duration endsAt;

  /// The line's text style; its colour is the "sung" colour.
  final TextStyle style;

  /// The song's position in milliseconds, read once a frame.
  final int Function() positionMs;

  const LyricWordSweep({
    super.key,
    required this.line,
    required this.endsAt,
    required this.style,
    required this.positionMs,
  });

  @override
  State<LyricWordSweep> createState() => _LyricWordSweepState();
}

class _LyricWordSweepState extends State<LyricWordSweep> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final ValueNotifier<int> _pos = ValueNotifier(widget.positionMs());

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final ms = widget.positionMs();
      if (ms != _pos.value) _pos.value = ms; // paused: no change, no frame
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.line.words!;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final sung = widget.style.color ?? Colors.white;
    final ahead = sung.withValues(alpha: sung.a * 0.42);
    return ValueListenableBuilder<int>(
      valueListenable: _pos,
      builder: (context, ms, _) => Text.rich(
        TextSpan(
          style: widget.style,
          children: [
            for (var i = 0; i < words.length; i++)
              TextSpan(
                text: i == 0 ? words[i].text : ' ${words[i].text}',
                style: TextStyle(
                  color: Color.lerp(
                    ahead,
                    sung,
                    reduce
                        ? (ms >= words[i].timestamp.inMilliseconds ? 1.0 : 0.0)
                        : Curves.easeOut.transform(wordProgress(words, i, widget.endsAt, ms)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
