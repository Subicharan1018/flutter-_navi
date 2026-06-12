// =============================================================================
// ModelStatusSheet — displays GET /model/status data.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/shuffle_providers.dart';

class ModelStatusSheet extends ConsumerWidget {
  const ModelStatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(modelStatusProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: statusAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Error loading model status',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(e.toString(), style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(modelStatusProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (status) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Model Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.username,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Stats list
            _StatTile(
              icon: Icons.build_circle_outlined,
              label: 'Built At',
              value: status.builtAtFormatted,
            ),
            _StatTile(
              icon: Icons.play_arrow_rounded,
              label: 'Plays Processed',
              value: status.totalPlaysProcessed.toString(),
            ),
            _StatTile(
              icon: Icons.library_music_outlined,
              label: 'Songs in Library',
              value: status.songsInLibrary.toString(),
            ),
            _StatTile(
              icon: Icons.people_outline_rounded,
              label: 'Composers Tracked',
              value: status.composersTracked.toString(),
            ),
            _StatTile(
              icon: Icons.link_rounded,
              label: 'Songs with Pairings',
              value: status.songsWithPairings.toString(),
            ),
            _StatTile(
              icon: Icons.play_circle_outline_rounded,
              label: 'Starter Contexts',
              value: status.starterContexts.toString(),
            ),
            _StatTile(
              icon: Icons.pending_actions_rounded,
              label: 'Unprocessed Events',
              value: status.unprocessedEvents.toString(),
              valueColor: status.unprocessedEvents > status.rebuildThreshold
                  ? theme.colorScheme.error
                  : null,
            ),
            _StatTile(
              icon: Icons.storage_outlined,
              label: 'Model Size',
              value: '${status.modelSizeMb.toStringAsFixed(2)} MB',
            ),
            if (status.unprocessedEvents > status.rebuildThreshold) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: theme.colorScheme.onErrorContainer,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Model rebuild will trigger after '
                          '${status.rebuildThreshold} events.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: valueColor ?? theme.colorScheme.primary,
        ),
      ),
    );
  }
}
