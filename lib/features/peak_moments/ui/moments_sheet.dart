import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../data/peak_mark.dart';
import '../data/peak_store.dart';
import '../logic/reel.dart' show momentSpan;

/// "Edit Moments…": each saved moment of [song] with -1 s / +1 s buttons for
/// its start and its end, and Remove. The same limits as dragging on the bar.
Future<void> showMomentsSheet(BuildContext context, Song song) =>
    showPlatformSheet<void>(context: context, title: 'Moments', builder: (_) => MomentsSheet(song: song));

class MomentsSheet extends ConsumerWidget {
  const MomentsSheet({super.key, required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final marks = ref.watch(songMarksProvider(song.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      child: marks.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xl),
              child: Text(
                'No saved moments in this song. Tap the flame while it plays to save one.',
                textAlign: TextAlign.center,
                style: t.footnote,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(song.title, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                for (final (i, m) in marks.indexed) ...[
                  const SizedBox(height: Space.lg),
                  _MomentEditor(song: song, mark: m, index: i + 1),
                ],
              ],
            ),
    );
  }
}

class _MomentEditor extends ConsumerWidget {
  const _MomentEditor({required this.song, required this.mark, required this.index});
  final Song song;
  final PeakMark mark;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final store = ref.read(peakMarksProvider.notifier);
    final dur = song.duration * 1000;
    void nudge({int start = 0, int end = 0}) =>
        store.nudge(song.id, mark.id, startDeltaMs: start, endDeltaMs: end, durationMs: dur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Moment $index · ${momentSpan(mark.startMs, mark.endMs)} · ${(mark.lengthMs / 1000).round()} s',
                style: t.body,
              ),
            ),
            CupertinoTap(
              label: 'Remove moment $index',
              onTap: () => store.removeNear(song.id, mark.startMs),
              child: NaviIcon(NaviGlyph.trash, size: 20, color: t.danger),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        _NudgeRow(
          label: 'Start',
          value: momentSpan(mark.startMs, mark.startMs).split('–').first,
          onEarlier: () => nudge(start: -1000),
          onLater: () => nudge(start: 1000),
        ),
        _NudgeRow(
          label: 'End',
          value: momentSpan(mark.endMs, mark.endMs).split('–').first,
          onEarlier: () => nudge(end: -1000),
          onLater: () => nudge(end: 1000),
        ),
      ],
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow({required this.label, required this.value, required this.onEarlier, required this.onLater});
  final String label;
  final String value;
  final VoidCallback onEarlier;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: t.subheadline)),
          Expanded(
            child: Text(value, style: t.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          _NudgeButton(text: '−1 s', semantic: '$label one second earlier', onTap: onEarlier),
          const SizedBox(width: Space.sm),
          _NudgeButton(text: '+1 s', semantic: '$label one second later', onTap: onLater),
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.text, required this.semantic, required this.onTap});
  final String text;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoTap(
      label: semantic,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 44, // a comfortable touch target
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.capsule)),
        child: Text(text, style: t.callout.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// [CupertinoClickable] (focusable for a TV d-pad and keyboard) with a label.
class CupertinoTap extends StatelessWidget {
  const CupertinoTap({super.key, required this.child, required this.onTap, required this.label});
  final Widget child;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) =>
      CupertinoClickable(onTap: onTap, semanticLabel: label, focusRadius: Radii.capsule, child: child);
}
