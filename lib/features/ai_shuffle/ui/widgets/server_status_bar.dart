// =============================================================================
// ServerStatusBar — compact status strip at the top of Smart Shuffle screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
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
    final tokens = ThemeTokens.of(context);

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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        color: tokens.bgSurface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _getDotColor(healthAsync, theme),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _getText(healthAsync),
              style: tokens.textStyle(
                12,
                FontWeight.w500,
                tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDotColor(
    AsyncValue<HealthResponse> asyncValue,
    ThemeData theme,
  ) {
    return asyncValue.when(
      data: (health) => health.isHealthy
          ? const Color(0xFF1DB954)
          : theme.colorScheme.error,
      loading: () => theme.colorScheme.onSurfaceVariant,
      error: (_, _) => theme.colorScheme.error,
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
      error: (_, _) => 'Tap to reconnect',
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
                  trailing: Text(
                    '${health.weather!.moodIcon} ${health.weather!.mood}',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
