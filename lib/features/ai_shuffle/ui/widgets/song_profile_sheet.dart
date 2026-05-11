import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/shuffle_providers.dart';

class SongProfileSheet extends ConsumerWidget {
  final String songTitle;

  const SongProfileSheet({super.key, required this.songTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(songProfileProvider(songTitle));
    final theme = Theme.of(context);

    return SafeArea(
      child: profileAsync.when(
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
                Text('Error loading profile', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(e.toString(), style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(songProfileProvider(songTitle)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.song,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (profile.behavioural.isNotEmpty) ...[
                _buildSectionTitle('Behavioural', theme),
                _buildTable(profile.behavioural, theme),
                const SizedBox(height: 16),
              ],
              if (profile.acoustic.isNotEmpty) ...[
                _buildSectionTitle('Acoustic', theme),
                _buildTable(profile.acoustic, theme),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTable(Map<String, dynamic> data, ThemeData theme) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1),
      },
      children: data.entries.map((e) {
        return TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                e.key,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                e.value.toString(),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
