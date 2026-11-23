import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer;

import '../../../core/focus/navi_focus.dart';
import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../player/audio_quality.dart' show StreamQuality;
import '../../../player/player_controls.dart' show Scrubber;
import '../data/peak_mark.dart';
import '../data/peak_store.dart';

/// The Now Playing [Scrubber] with this song's saved moments drawn under the
/// bar (each with a handle on both ends to drag), and backward scrubs logged
/// so "most replayed" can be found later.
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

/// Bands under the bar, one per saved moment, each with a handle at its start
/// and at its end. Sized by its parent (the scrubber track); [totalMs] is the
/// song length.
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
          for (final m in marks)
            _Band(key: ValueKey(m.id), songId: songId, mark: m, others: marks, totalMs: totalMs, width: c.maxWidth),
        ],
      ),
    );
  }
}

class _Band extends ConsumerStatefulWidget {
  const _Band({
    super.key,
    required this.songId,
    required this.mark,
    required this.others,
    required this.totalMs,
    required this.width,
  });
  final String songId;
  final PeakMark mark;
  final List<PeakMark> others;
  final int totalMs;
  final double width;

  @override
  ConsumerState<_Band> createState() => _BandState();
}

class _BandState extends ConsumerState<_Band> {
  /// The mark as the finger has it while a handle is held; null otherwise.
  PeakMark? _preview;

  /// The finger's own position (ms), kept apart from the clamped preview so
  /// a drag past a limit does not lose where the finger really is.
  double _rawStart = 0;
  double _rawEnd = 0;

  static const _barY = 22.0; // under the 6 dp bar, inside the 32 dp band
  static const _handle = 28.0;
  static const _nudgeMs = 1000;

  PeakMark get _shown => _preview ?? widget.mark;

  double _msPerPx() => widget.totalMs / widget.width;

  void _begin() {
    _rawStart = widget.mark.startMs.toDouble();
    _rawEnd = widget.mark.endMs.toDouble();
  }

  void _dragStart(DragUpdateDetails d) {
    _rawStart += d.delta.dx * _msPerPx();
    setState(() {
      _preview = widget.mark.adjusted(widget.others, startMs: _rawStart.round(), durationMs: widget.totalMs);
    });
  }

  void _dragEnd(DragUpdateDetails d) {
    _rawEnd += d.delta.dx * _msPerPx();
    setState(() {
      _preview = widget.mark.adjusted(widget.others, endMs: _rawEnd.round(), durationMs: widget.totalMs);
    });
  }

  /// Saves what the handle was dragged to; [start] says which edge moved.
  void _commit({required bool start}) {
    final p = _preview;
    setState(() => _preview = null);
    if (p == null) return;
    ref
        .read(peakMarksProvider.notifier)
        .setBounds(
          widget.songId,
          widget.mark.id,
          startMs: start ? p.startMs : null,
          endMs: start ? null : p.endMs,
          durationMs: widget.totalMs,
        );
  }

  void _nudge({int start = 0, int end = 0}) => ref
      .read(peakMarksProvider.notifier)
      .nudge(widget.songId, widget.mark.id, startDeltaMs: start, endDeltaMs: end, durationMs: widget.totalMs);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final w = widget.width;
    final m = _shown;
    final left = m.startMs / widget.totalMs * w;
    final right = m.endMs / widget.totalMs * w;
    // Two handles never overlap: a short band gives each half its width.
    final box = (right - left).clamp(0.0, _handle);
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
        _Handle(
          key: const ValueKey('start'),
          x: left,
          width: box,
          label: 'Moment start',
          value: _clock(m.startMs),
          onBegin: _begin,
          onDrag: _dragStart,
          onEnd: () => _commit(start: true),
          onNudge: (dir) => _nudge(start: dir * _nudgeMs),
        ),
        _Handle(
          key: const ValueKey('end'),
          x: right,
          width: box,
          label: 'Moment end',
          value: _clock(m.endMs),
          onBegin: _begin,
          onDrag: _dragEnd,
          onEnd: () => _commit(start: false),
          onNudge: (dir) => _nudge(end: dir * _nudgeMs),
        ),
      ],
    );
  }
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One draggable end of a moment. Left / Right (a keyboard, a TV remote's
/// d-pad) move it a second at a time, and so do a screen reader's increase
/// and decrease.
class _Handle extends StatelessWidget {
  const _Handle({
    super.key,
    required this.x,
    required this.width,
    required this.label,
    required this.value,
    required this.onBegin,
    required this.onDrag,
    required this.onEnd,
    required this.onNudge,
  });

  final double x;
  final double width;
  final String label;
  final String value;
  final VoidCallback onBegin;
  final ValueChanged<DragUpdateDetails> onDrag;
  final VoidCallback onEnd;
  final ValueChanged<int> onNudge;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      onNudge(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      onNudge(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Positioned(
      left: x - width / 2,
      top: 16,
      width: width,
      height: 16,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: NaviFocusRing(
          radius: 8,
          onTap: () {},
          child: Semantics(
            label: label,
            value: value,
            increasedValue: 'a second later',
            decreasedValue: 'a second earlier',
            onIncrease: () => onNudge(1),
            onDecrease: () => onNudge(-1),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => onBegin(),
              onHorizontalDragUpdate: onDrag,
              onHorizontalDragEnd: (_) => onEnd(),
              onHorizontalDragCancel: onEnd,
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
      ),
    );
  }
}
