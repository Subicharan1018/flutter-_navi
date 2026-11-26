import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/equalizer/ui/equalizer_screen.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/playback_tuning.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/desktop_dialogs.dart';

String formatSpeed(double speed) {
  final s = speed.toStringAsFixed(2);
  return '${s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}×';
}

/// Now Playing "more" row: playback speed (0.5–2×).
class PlaybackSpeedTile extends ConsumerWidget {
  const PlaybackSpeedTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final speed = ref.watch(settingsProvider.select((s) => s.playbackSpeed));
    return ListTile(
      leading: NaviIcon(
        NaviGlyph.gauge,
        color: speed == 1.0 ? t.textSecondary : t.accent,
      ),
      title: const Text('Playback speed'),
      subtitle: Text(speed == 1.0 ? 'Normal' : formatSpeed(speed)),
      trailing: NaviIcon(NaviGlyph.chevron, color: t.textMuted),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const _SpeedSheet(),
      ),
    );
  }
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final speed = ref.watch(settingsProvider.select((s) => s.playbackSpeed));
    final notifier = ref.read(settingsProvider.notifier);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Playback speed',
              style: naviText(20, FontWeight.w700, t.textPrimary),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                formatSpeed(speed),
                style: naviText(34, FontWeight.w700, t.textPrimary),
              ),
            ),
            Slider(
              value: speed,
              min: kMinPlaybackSpeed,
              max: kMaxPlaybackSpeed,
              divisions: 30,
              activeColor: t.accent,
              onChanged: notifier.setPlaybackSpeed,
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final p in const [0.75, 1.0, 1.25, 1.5, 2.0])
                  ChoiceChip(
                    label: Text(formatSpeed(p)),
                    selected: (speed - p).abs() < 0.001,
                    onSelected: (_) => notifier.setPlaybackSpeed(p),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Now Playing "more" row: the equalizer. Renders nothing where there is none.
class EqualizerTile extends ConsumerWidget {
  const EqualizerTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(audioHandlerProvider).equalizer;
    if (!eq.isSupported) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return ListTile(
      leading: NaviIcon(NaviGlyph.sliders, color: t.textSecondary),
      title: const Text('Equalizer'),
      trailing: NaviIcon(NaviGlyph.chevron, color: t.textMuted),
      onTap: () => showPlatformSheet<void>(
        context: context,
        title: 'Equalizer',
        maxWidth: 760,
        builder: (_) => EqualizerPanel(equalizer: eq),
      ),
    );
  }
}
