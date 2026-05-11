import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/shuffle_providers.dart';
import '../../data/models/health_response.dart';

class ServerStatusBar extends ConsumerWidget {
  const ServerStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(serverHealthProvider);
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        if (healthAsync.hasValue) {
          _showDetailsSheet(context, healthAsync.value);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        color: _getBackgroundColor(healthAsync, theme),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIcon(healthAsync),
              size: 14,
              color: _getTextColor(healthAsync, theme),
            ),
            const SizedBox(width: 8),
            Text(
              _getText(healthAsync),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _getTextColor(healthAsync, theme),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor(
      AsyncValue<HealthResponse> asyncValue, ThemeData theme) {
    return asyncValue.when(
      data: (health) => health.isHealthy
          ? theme.colorScheme.tertiary
          : theme.colorScheme.error,
      loading: () => theme.colorScheme.surfaceContainerHighest,
      error: (_, __) => theme.colorScheme.error,
    );
  }

  Color _getTextColor(AsyncValue<HealthResponse> asyncValue, ThemeData theme) {
    return asyncValue.when(
      data: (health) => health.isHealthy
          ? theme.colorScheme.onTertiary
          : theme.colorScheme.onError,
      loading: () => theme.colorScheme.onSurfaceVariant,
      error: (_, __) => theme.colorScheme.onError,
    );
  }

  IconData _getIcon(AsyncValue<HealthResponse> asyncValue) {
    return asyncValue.when(
      data: (health) => health.isHealthy ? Icons.check_circle : Icons.error,
      loading: () => Icons.sync,
      error: (_, __) => Icons.cloud_off,
    );
  }

  String _getText(AsyncValue<HealthResponse> asyncValue) {
    return asyncValue.when(
      data: (health) => health.isHealthy
          ? 'Server Online · ${health.librarySize} songs'
          : 'Server Offline',
      loading: () => 'Checking server…',
      error: (_, __) => 'Server Offline',
    );
  }

  void _showDetailsSheet(BuildContext context, HealthResponse? health) {
    if (health == null) return;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Server Status',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Status'),
                trailing: Text(health.status.toUpperCase()),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Uptime'),
                trailing: Text(health.uptime),
              ),
              ListTile(
                leading: const Icon(Icons.library_music_outlined),
                title: const Text('Library Size'),
                trailing: Text('${health.librarySize} songs'),
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('Model Loaded'),
                trailing: Text(health.modelLoaded ? 'Yes' : 'No'),
              ),
            ],
          ),
        );
      },
    );
  }
}
