import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/shuffle_providers.dart';

class SessionControlsSheet extends ConsumerWidget {
  const SessionControlsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Session Controls',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reset Session'),
            onTap: () async {
              try {
                await ref.read(shuffleRepositoryProvider).resetSession();
                ref.read(shuffleQueueProvider.notifier).clearQueue();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session reset')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reset failed: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Session Status'),
            onTap: () {
              Navigator.pop(context);
              _showSessionStatusSheet(context);
            },
          ),
        ],
      ),
    );
  }

  void _showSessionStatusSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _SessionStatusSheet(),
    );
  }
}

class _SessionStatusSheet extends ConsumerWidget {
  const _SessionStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(sessionStatusProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: statusAsync.when(
        loading: () => const SizedBox(
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(
          height: 150,
          child: Center(
            child: Text('Error loading status: $e'),
          ),
        ),
        data: (status) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Session Status',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Session ID'),
              trailing: Text(status.sessionId, style: theme.textTheme.bodySmall),
            ),
            ListTile(
              title: const Text('Song Count'),
              trailing: Text(status.songCount.toString()),
            ),
            ListTile(
              title: const Text('Started At'),
              trailing: Text(status.startedAtFormatted),
            ),
          ],
        ),
      ),
    );
  }
}
