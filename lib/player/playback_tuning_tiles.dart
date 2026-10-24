import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/hive_boxes.dart';
import '../core/theme.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/playback_tuning.dart';
import '../widgets/art/navi_icons.dart';

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

/// Now Playing "more" row: Android equalizer. Renders nothing elsewhere.
class EqualizerTile extends ConsumerWidget {
  const EqualizerTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(audioHandlerProvider).equalizer;
    if (eq == null) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return ListTile(
      leading: NaviIcon(NaviGlyph.sliders, color: t.textSecondary),
      title: const Text('Equalizer'),
      trailing: NaviIcon(NaviGlyph.chevron, color: t.textMuted),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _EqualizerSheet(equalizer: eq),
      ),
    );
  }
}

class _EqualizerSheet extends StatefulWidget {
  final AndroidEqualizer equalizer;
  const _EqualizerSheet({required this.equalizer});

  @override
  State<_EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<_EqualizerSheet> {
  late final Future<AndroidEqualizerParameters> _params =
      widget.equalizer.parameters;
  late bool _enabled = HiveBoxes.prefs.get(HiveBoxes.kEqualizerEnabled) == true;

  Future<void> _setEnabled(bool v) async {
    setState(() => _enabled = v);
    await widget.equalizer.setEnabled(v);
    await HiveBoxes.prefs.put(HiveBoxes.kEqualizerEnabled, v);
  }

  Future<void> _setBand(
    AndroidEqualizerParameters p,
    AndroidEqualizerBand band,
    double gain,
  ) async {
    await band.setGain(gain);
    await HiveBoxes.prefs.put(HiveBoxes.kEqualizerGains, [
      for (final b in p.bands) b.gain,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Equalizer',
                    style: naviText(20, FontWeight.w700, t.textPrimary),
                  ),
                ),
                Switch(
                  value: _enabled,
                  activeTrackColor: t.accent,
                  onChanged: _setEnabled,
                ),
              ],
            ),
            FutureBuilder<AndroidEqualizerParameters>(
              future: _params,
              builder: (context, snap) {
                final p = snap.data;
                if (p == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      snap.hasError
                          ? 'The equalizer isn’t available yet. Start a song, then try again.'
                          : 'Loading bands…',
                      style: TextStyle(color: t.textMuted),
                    ),
                  );
                }
                return SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      for (final band in p.bands)
                        Expanded(
                          child: _BandSlider(
                            band: band,
                            min: p.minDecibels,
                            max: p.maxDecibels,
                            enabled: _enabled,
                            onChangeEnd: (g) => _setBand(p, band, g),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChangeEnd;
  const _BandSlider({
    required this.band,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final hz = band.centerFrequency;
    final label = hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k'
        : hz.round().toString();
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<double>(
            stream: band.gainStream,
            initialData: band.gain,
            builder: (context, snap) => RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: (snap.data ?? 0).clamp(min, max).toDouble(),
                min: min,
                max: max,
                activeColor: t.accent,
                onChanged: enabled ? band.setGain : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            ),
          ),
        ),
        Text(label, style: TextStyle(color: t.textMuted, fontSize: 11)),
      ],
    );
  }
}
