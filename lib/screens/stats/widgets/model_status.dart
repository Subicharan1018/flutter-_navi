import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../features/ai_shuffle/data/models/model_status_response.dart';
import '../../../utils/format.dart';
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
                  ? 'Updating your mixes with your latest plays now.'
                  : 'Your mixes update after ${threshold - pending} more plays.',
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
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: figureStyle(t, 22))),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        ],
      ),
    );
  }
}
