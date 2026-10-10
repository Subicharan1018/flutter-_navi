import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/model_status_response.dart';
import '../../../utils/format.dart';
import 'stat_card.dart';

/// What the Smart Shuffle model has learned and when it next retrains.
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

    return StatCard(
      title: 'Smart Shuffle Model',
      readout: learning ? 'Learning' : 'Up to Date',
      readoutColor: learning ? t.accent : t.textSecondary,
      readoutCaption: '${status.modelSizeMb.toStringAsFixed(1)} MB on your server',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Figure(value: compactCount(status.songsInLibrary), label: 'songs'),
              _Figure(value: compactCount(status.totalPlaysProcessed), label: 'plays learned'),
              _Figure(value: '${status.composersTracked}', label: 'composers'),
              _Figure(value: '${status.contextBuckets}', label: 'moments'),
            ],
          ),
          if (threshold > 0) ...[
            const SizedBox(height: Space.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(height: 4, color: t.fill),
                  FractionallySizedBox(widthFactor: progress, child: Container(height: 4, color: t.accent)),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              pending >= threshold
                  ? 'Retraining with your latest plays.'
                  : 'Retrains after ${threshold - pending} more plays.',
              style: t.footnote,
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
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: figureStyle(t, 20))),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption1),
        ],
      ),
    );
  }
}
