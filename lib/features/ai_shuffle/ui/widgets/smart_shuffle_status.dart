import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../screens/stats/widgets/model_status.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/desktop_dialogs.dart';
import '../../../../widgets/ui/grouped_list.dart';
import '../../../../widgets/ui/states.dart';
import '../../data/models/health_response.dart';
import '../../logic/shuffle_providers.dart';
import '../smart_shuffle_login_screen.dart';

/// Nav-bar button for Smart Shuffle's server: a glyph with a status dot
/// (white online, red offline). Opens the server + model sheet, or sign-in
/// when the server rejected our credentials.
class SmartShuffleStatusButton extends ConsumerWidget {
  const SmartShuffleStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final health = ref.watch(serverHealthProvider);
    final dot = health.when(
      data: (h) => h.isHealthy ? t.positive : t.danger,
      loading: () => t.textMuted,
      error: (_, _) => t.danger,
    );
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => health.hasError
          ? Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SmartShuffleLoginScreen()))
          : showPlatformSheet<void>(context: context, title: 'Smart Shuffle', builder: (_) => const _StatusSheet()),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const NaviIcon(NaviGlyph.smartShuffle, size: 26, semanticLabel: 'Smart Shuffle status'),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: t.bgBase, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSheet extends ConsumerWidget {
  const _StatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(serverHealthProvider);
    final model = ref.watch(modelStatusProvider);
    final HealthResponse? h = health.asData?.value;
    final w = h?.weather;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupedSection(
          header: 'Server',
          children: [
            GroupedRow(
              title: 'Status',
              icon: NaviGlyph.radio,
              value: health.isLoading ? 'Checking…' : (h?.isHealthy == true ? 'Online' : 'Offline'),
            ),
            if (w != null) ...[
              GroupedRow(
                title: 'Weather',
                icon: NaviGlyph.cloud,
                value: '${w.moodIcon} ${w.mood}',
              ),
              GroupedRow(
                title: 'Temperature',
                icon: NaviGlyph.thermometer,
                value: '${w.temperatureC.toStringAsFixed(1)}°C',
              ),
              GroupedRow(
                title: 'Humidity',
                icon: NaviGlyph.drop,
                value: '${w.humidityPct}%',
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: model.when(
            data: (m) => ModelStatusCard(status: m),
            loading: () => const LoadingState(),
            error: (_, _) => MessageState.error(
              title: 'Model status isn’t available',
              onRetry: () => ref.invalidate(modelStatusProvider),
            ),
          ),
        ),
      ],
    );
  }
}
