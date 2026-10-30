import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup, showToast;
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/controls.dart' show FilterPills;
import '../../../widgets/ui/media.dart';
import '../../listen/data/listen_models.dart';
import '../logic/flow_controller.dart';

/// "Any mood" in the chips, which key the moods by their server name.
const String _anyMood = '';

/// Home's Flow: an endless stream of songs you know and ones you haven't
/// heard. Pick a mood chip if you like, tap Start, and the queue keeps filling.
class FlowSection extends ConsumerWidget {
  const FlowSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final flow = ref.watch(flowProvider);
    final moods = ref.watch(flowMoodsProvider).asData?.value ?? const <FlowMood>[];
    final controller = ref.read(flowProvider.notifier);
    final blurb = flow.active
        ? (flow.mood == null ? 'Playing songs you know and new ones, picked as you go.' : 'Playing ${flow.mood} songs, picked as you go.')
        : 'An endless mix of songs you know and ones you haven’t heard, tuned by what you skip and star.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NaviIcon(NaviGlyph.flow, size: 24, color: t.textPrimary),
                  const SizedBox(width: Space.sm),
                  Semantics(header: true, child: Text('Flow', style: t.title2)),
                ],
              ),
              const SizedBox(height: Space.xxs),
              Text(blurb, style: t.footnote),
            ],
          ),
        ),
        if (moods.isNotEmpty)
          FilterPills<String>(
            options: {_anyMood: 'Any mood', for (final m in moods) m.mood: m.label},
            value: flow.mood ?? _anyMood,
            onChanged: (v) => controller.selectMood(v == _anyMood ? null : v),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (flow.active)
                TintedButton(label: 'Stop Flow', glyph: NaviGlyph.flow, height: 50, onTap: controller.stop)
              else
                TintedButton(
                  label: flow.starting ? 'Starting…' : 'Start Flow',
                  glyph: NaviGlyph.flow,
                  filled: true,
                  height: 50,
                  onTap: flow.starting
                      ? null
                      : () async {
                          final ok = await controller.start();
                          if (!ok && context.mounted) showToast(context, ref.read(flowProvider).error ?? 'Flow couldn’t start.');
                        },
                ),
              if (flow.active && flow.blend.total > 0) ...[
                const SizedBox(height: Space.md),
                FlowBlendStrip(blend: flow.blend),
              ],
              if (flow.error != null) ...[
                const SizedBox(height: Space.sm),
                Text(flow.error!, style: t.footnote.copyWith(color: t.danger)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// What the last batch was made of, as a thin bar and a line under it:
/// Familiar · Fresh · New language, darkest to lightest.
class FlowBlendStrip extends StatelessWidget {
  final FlowBlend blend;
  const FlowBlendStrip({super.key, required this.blend});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final parts = [
      ('Familiar', blend.familiar, t.textMuted),
      ('Fresh', blend.fresh, t.textSecondary),
      ('New language', blend.explore, t.textPrimary),
    ];
    return Semantics(
      label: 'Last batch: ${blend.familiar} familiar, ${blend.fresh} fresh, ${blend.explore} in a new language',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Row(
                  children: [
                    for (final (_, n, color) in parts)
                      if (n > 0) Expanded(flex: n, child: ColoredBox(color: color)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              children: [
                for (final (label, n, color) in parts)
                  if (n > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(dimension: 8, child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
                        const SizedBox(width: Space.xs),
                        Text('$label $n', style: t.footnote),
                      ],
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The mood choices as a sheet (Now Playing's pill opens it).
Future<void> showFlowMoodSheet(BuildContext context, WidgetRef ref) {
  final moods = ref.read(flowMoodsProvider).asData?.value ?? const <FlowMood>[];
  final current = ref.read(flowProvider).mood;
  return showPlatformSheet<void>(
    context: context,
    title: 'Flow mood',
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      Widget pick(String label, String? mood) => SheetAction(
            label: label,
            trailing: mood == current ? NaviIcon(NaviGlyph.check, size: 21, color: t.accent) : null,
            onTap: () => ref.read(flowProvider.notifier).selectMood(mood),
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          pick('Any mood', null),
          for (final m in moods) pick(m.label, m.mood),
        ]),
      );
    },
  );
}
