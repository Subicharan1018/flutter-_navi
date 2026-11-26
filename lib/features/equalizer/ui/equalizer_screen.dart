import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive, showChoiceSheet, showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/states.dart';
import '../logic/eq_model.dart';
import '../logic/equalizer_service.dart';
import 'eq_curve.dart';

/// Settings ▸ Playback ▸ Equalizer, and the same page from Now Playing.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(audioHandlerProvider).equalizer;
    return LargeTitlePage(
      title: 'Equalizer',
      slivers: [
        SliverToBoxAdapter(
          child: eq.isSupported
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: EqualizerPanel(equalizer: eq),
                  ),
                )
              : const MessageState(
                  art: EmptyArtKind.noResults,
                  title: 'No equalizer here',
                  message: 'The browser version can’t change the sound. The Android, TV and Windows apps have the equalizer.',
                ),
        ),
      ],
    );
  }
}

/// The switch, presets, curve and Reset.
class EqualizerPanel extends StatelessWidget {
  final EqualizerService equalizer;
  const EqualizerPanel({super.key, required this.equalizer});

  Future<void> _pickPreset(BuildContext context) async {
    final saved = equalizer.customPresets;
    final options = <EqPreset>[...saved, ...kBuiltInPresets];
    final current = equalizer.preset;
    final picked = await showChoiceSheet<EqPreset>(
      context,
      title: 'Presets',
      options: options,
      selected: options.firstWhere(
        (p) => p.name == current?.name,
        orElse: () => const EqPreset('', []),
      ),
      label: (p) => p.name,
    );
    if (picked != null) await equalizer.selectPreset(picked);
  }

  Future<void> _save(BuildContext context) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || !context.mounted) return;
    final ok = await equalizer.savePreset(name);
    if (!ok && context.mounted) {
      showToast(context, name.trim().isEmpty ? 'Give the preset a name' : '“${name.trim()}” is a built-in preset');
    }
  }

  Future<void> _delete(BuildContext context) async {
    final name = equalizer.preset?.name;
    if (name == null) return;
    final sure = await confirmDestructive(
      context,
      title: 'Delete “$name”?',
      message: 'The sound stays as it is now.',
      confirmLabel: 'Delete',
    );
    if (sure) await equalizer.deletePreset();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ListenableBuilder(
      listenable: equalizer,
      builder: (context, _) {
        final on = equalizer.enabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GroupedSwitchRow(title: 'Equalizer', value: on, onChanged: equalizer.setEnabled),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: Space.md,
                children: [
                  TextButton(
                    onPressed: on ? () => _pickPreset(context) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: t.textPrimary,
                      disabledForegroundColor: t.textMuted,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 48),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Preset', style: t.body.copyWith(color: t.textSecondary)),
                        const SizedBox(width: Space.md),
                        Flexible(
                          child: Text(
                            equalizer.preset?.name ?? 'Custom',
                            overflow: TextOverflow.ellipsis,
                            style: t.headline.copyWith(color: on ? t.textPrimary : t.textMuted),
                          ),
                        ),
                        const SizedBox(width: Space.xs),
                        RotatedBox(
                          quarterTurns: 1,
                          child: NaviIcon(NaviGlyph.chevron, size: 18, color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (equalizer.canSave || equalizer.canDelete)
                    TextButton(
                      onPressed: !on
                          ? null
                          : () => equalizer.canSave ? _save(context) : _delete(context),
                      style: TextButton.styleFrom(
                        foregroundColor: t.textSecondary,
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(equalizer.canSave ? 'Save preset' : 'Delete preset'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: EqCurve(
                gains: equalizer.gains,
                enabled: on,
                onChanged: equalizer.setBand,
                onChangeEnd: equalizer.commitCurve,
              ),
            ),
            const SizedBox(height: Space.md),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: OutlinedButton(
                  onPressed: on && !isFlat(equalizer.gains) ? equalizer.reset : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.textPrimary,
                    side: BorderSide(color: t.outline),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(96, 44),
                  ),
                  child: const Text('Reset'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                'Off, or with a flat curve, the sound is not touched. Boosting a band turns '
                'the whole song down by the same amount, so nothing distorts.',
                style: t.footnote,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AlertDialog(
      title: const Text('Save preset'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: t.accent,
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: t.body.copyWith(color: t.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text('Save', style: t.headline.copyWith(color: t.accent)),
        ),
      ],
    );
  }
}
