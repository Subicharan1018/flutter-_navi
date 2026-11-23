import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/model_status_response.dart';
import '../../../utils/format.dart';
import 'learning_blob.dart';
import 'stat_card.dart';

/// What Smart Shuffle has learned about you, and when it next updates.
class ModelStatusCard extends StatelessWidget {
  final ModelStatusResponse status;
  const ModelStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final pending = status.unprocessedEvents;
    final threshold = status.rebuildThreshold;
    final progress = threshold > 0 ? (pending / threshold).clamp(0.0, 1.0) : 0.0;
    final learning = pending > 0;

    return StatSection(
      title: 'Smart Shuffle',
      emphasis: StatEmphasis.quiet,
      readout: learning ? 'Learning' : 'Up to Date',
      readoutColor: learning ? t.accent : t.textSecondary,
      readoutCaption: learning ? 'from your latest plays' : 'with everything you’ve played',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Figure(value: compactCount(status.totalPlaysProcessed), label: 'plays learned'),
              _Figure(value: compactCount(status.songsInLibrary), label: 'songs known'),
              _Figure(value: '${status.contextBuckets}', label: 'listening moments'),
            ],
          ),
          if (threshold > 0) ...[
            const SizedBox(height: Space.lg),
            Row(
              children: [
                // The model as a drop: it swells toward its next rebuild and
                // wobbles while it is learning. Still when up to date.
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      LearningBlob(fill: progress, alive: learning),
                      Text('${(progress * 100).round()}%', style: figureStyle(t, 17).copyWith(color: t.onAccent)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Text(
                    pending >= threshold
                        ? 'Updating your mixes with your latest plays now.'
                        : '$pending of $threshold plays collected. Your mixes update after ${threshold - pending} more.',
                    style: t.subheadline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;
  const _Figure({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: figureStyle(t, 22))),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        ],
      ),
    );
  }
}
