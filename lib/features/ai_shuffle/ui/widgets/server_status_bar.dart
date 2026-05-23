// =============================================================================
// ServerStatusBar — compact status strip at the top of Smart Shuffle screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/shuffle_providers.dart';
import '../../data/models/health_response.dart';
import '../../../../widgets/desktop_dialogs.dart';
import '../smart_shuffle_login_screen.dart';

class ServerStatusBar extends ConsumerWidget {
  const ServerStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(serverHealthProvider);
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        healthAsync.whenOrNull(
          data: (h) => _showDetailsSheet(context, h),
          error: (e, _) {
            // On auth error → show login screen.
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SmartShuffleLoginScreen(),
              ),
            );
          },
        );
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
      data: (health) =>
          health.isHealthy ? Icons.check_circle : Icons.error,
      loading: () => Icons.sync,
      error: (_, __) => Icons.cloud_off,
    );
  }

  String _getText(AsyncValue<HealthResponse> asyncValue) {
    return asyncValue.when(
      data: (health) {
        if (!health.isHealthy) return 'Server Offline';
        final w = health.weather;
        if (w != null) {
          return 'Smart Shuffle Online · ${w.moodIcon} ${w.temperatureC.toStringAsFixed(1)}°C';
        }
        return 'Smart Shuffle Online';
      },
      loading: () => 'Checking server…',
      error: (_, __) => 'Tap to reconnect',
    );
  }

  void _showDetailsSheet(BuildContext context, HealthResponse health) {
    showPlatformSheet(
      context: context,
      title: 'Server Status',
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Status'),
                trailing: Text(health.status.toUpperCase()),
              ),
              if (health.weather != null) ...[
                ListTile(
                  leading: const Icon(Icons.thermostat_outlined),
                  title: const Text('Temperature'),
                  trailing: Text(
                    '${health.weather!.temperatureC.toStringAsFixed(1)}°C',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.water_drop_outlined),
                  title: const Text('Humidity'),
                  trailing: Text('${health.weather!.humidityPct}%'),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Weather Mood'),
                  trailing:
                      Text('${health.weather!.moodIcon} ${health.weather!.mood}'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
