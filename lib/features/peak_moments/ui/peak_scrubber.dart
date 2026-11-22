import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer;

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../player/audio_quality.dart' show StreamQuality;
import '../../../player/player_controls.dart' show Scrubber;
import '../data/peak_mark.dart';
import '../data/peak_store.dart';

/// The Now Playing [Scrubber] with this song's saved moments drawn under the
/// bar (each with a handle to drag its end), and backward scrubs logged so
/// "most replayed" can be found later.
class PeakScrubber extends ConsumerWidget {
  const PeakScrubber({super.key, required this.player, required this.song, this.stream, this.scrubberKey});

  final AudioPlayer player;
  final Song song;
  final StreamQuality? stream;
  final Key? scrubberKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marks = ref.watch(songMarksProvider(song.id));
    return Scrubber(
      key: scrubberKey,
      player: player,
      song: song,
      stream: stream,
      trackOverlay: marks.isEmpty ? null : (totalMs) => PeakBands(songId: song.id, marks: marks, totalMs: totalMs),
      onSeekEnd: (from, to) =>
          ref.read(seekLogProvider.notifier).recordSeek(song.id, fromMs: from.inMilliseconds, toMs: to.inMilliseconds),
    );
  }
}

/// Bands under the bar, one per saved moment, each ending in a drag handle.
/// Sized by its parent (the scrubber track); [totalMs] is the song length.
class PeakBands extends StatelessWidget {
  const PeakBands({super.key, required this.songId, required this.marks, required this.totalMs});
  final String songId;
  final List<PeakMark> marks;
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    if (totalMs <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final m in marks) _Band(key: ValueKey(m.id), songId: songId, mark: m, totalMs: totalMs, width: c.maxWidth),
        ],
      ),
    );
  }
}

class _Band extends ConsumerStatefulWidget {
  const _Band({super.key, required this.songId, required this.mark, required this.totalMs, required this.width});
  final String songId;
  final PeakMark mark;
  final int totalMs;
  final double width;

  @override
  ConsumerState<_Band> createState() => _BandState();
}

class _BandState extends ConsumerState<_Band> {
  /// Length while the handle is held; null otherwise.
  int? _dragLength;

  static const _barY = 22.0; // under the 6 dp bar, inside the 32 dp band
  static const _handle = 28.0;

  int get _length => _dragLength ?? widget.mark.lengthMs;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final w = widget.width;
    final left = widget.mark.startMs / widget.totalMs * w;
    final right = (widget.mark.startMs + _length) / widget.totalMs * w;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          width: (right - left).clamp(2.0, w),
          top: _barY,
          height: 3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(1.5)),
            ),
          ),
        ),
        Positioned(
          left: right - _handle / 2,
          top: 16,
          width: _handle,
          height: 16,
          child: Semantics(
            label: 'Moment length',
            value: '${(_length / 1000).round()} seconds',
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                final dMs = d.delta.dx / w * widget.totalMs;
                setState(() {
                  _dragLength = ((_dragLength ?? widget.mark.lengthMs) + dMs).round().clamp(
                    PeakMark.minLengthMs,
                    PeakMark.maxLengthMs,
                  );
                });
              },
              onHorizontalDragEnd: (_) => _commit(),
              onHorizontalDragCancel: _commit,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _commit() {
    final len = _dragLength;
    setState(() => _dragLength = null);
    if (len == null) return;
    ref.read(peakMarksProvider.notifier).resize(widget.songId, widget.mark.id, len, durationMs: widget.totalMs);
  }
}
