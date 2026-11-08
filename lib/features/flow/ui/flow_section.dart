import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup;
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/controls.dart' show FilterPills;
import '../../../widgets/ui/media.dart';
import '../../listen/data/listen_models.dart';
import '../logic/flow_controller.dart';

/// "Any mood" in the chips, which key the moods by their server name.
const String _anyMood = '';

/// Home's Flow: an endless stream of songs you know and ones you haven't
/// heard. Pick a mood chip if you like, tap Start, and the queue keeps filling.
/// On Windows it is one inline row (glyph, words, Start) with the moods under it.
class FlowSection extends ConsumerWidget {
  const FlowSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final flow = ref.watch(flowProvider);
    final moodsAsync = ref.watch(flowMoodsProvider);
    final moods = moodsAsync.asData?.value ?? const <FlowMood>[];
    final controller = ref.read(flowProvider.notifier);
    final desktop = PlatformUtils.isDesktop;
    final mood = flow.mood == null ? null : moods.where((m) => m.mood == flow.mood).firstOrNull?.label ?? flow.mood;
    final blurb = flow.active
        ? (mood == null ? 'Playing songs you know and new ones, picked as you go.' : 'Playing $mood songs, picked as you go.')
        : 'An endless mix of songs you know and ones you haven’t heard, tuned by what you skip and star.';

    final action = flow.active
        ? TintedButton(label: 'Stop Flow', glyph: NaviGlyph.flow, height: desktop ? 36 : 50, onTap: controller.stop)
        : TintedButton(
            label: flow.starting ? 'Starting…' : 'Start Flow',
            glyph: NaviGlyph.flow,
            filled: true,
            height: desktop ? 36 : 50,
            onTap: flow.starting ? null : controller.start,
          );

    final gutter = pageGutter(context);
    final header = desktop
        ? Row(
            children: [
              NaviIcon(NaviGlyph.flow, size: 24, color: t.textPrimary),
              const SizedBox(width: Space.md),
              Semantics(header: true, child: Text('Flow', style: t.title2)),
              const SizedBox(width: Space.lg),
              Expanded(child: Text(blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote)),
              const SizedBox(width: Space.lg),
              action,
            ],
          )
        : Column(
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
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: EdgeInsets.fromLTRB(gutter, Space.xxl, gutter, Space.md), child: header),
        if (moods.isNotEmpty) ...[
          if (desktop)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final e in {_anyMood: 'Any mood', for (final m in moods) m.mood: m.label}.entries)
                    _MoodChip(
                      label: e.value,
                      selected: (flow.mood ?? _anyMood) == e.key,
                      onTap: () => controller.selectMood(e.key == _anyMood ? null : e.key),
                    ),
                ],
              ),
            )
          else
            FilterPills<String>(
              options: {_anyMood: 'Any mood', for (final m in moods) m.mood: m.label},
              value: flow.mood ?? _anyMood,
              onChanged: (v) => controller.selectMood(v == _anyMood ? null : v),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, Space.xs, gutter, 0),
            child: Text(
              flow.active
                  ? 'Switching mood swaps the songs still to come.'
                  : (mood == null ? 'Starts with any mood.' : 'Starts with $mood.'),
              style: t.footnote,
            ),
          ),
        ] else if (moodsAsync.hasError)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: _InlineNote(
              text: 'Moods didn’t load.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(flowMoodsProvider),
            ),
          )
        else if (moodsAsync.hasValue)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Text('Mood choices show up once your songs have moods.', style: t.footnote),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.sm, gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!desktop) action,
              if (flow.active && flow.blend.total > 0) ...[
                const SizedBox(height: Space.md),
                FlowBlendStrip(blend: flow.blend),
              ],
              if (flow.error != null) ...[
                const SizedBox(height: Space.sm),
                _InlineNote(text: flow.error!, danger: true, actionLabel: 'Retry', onAction: flow.starting ? null : controller.retry),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One mood on Windows: a pill that washes on hover, shows the keyboard ring,
/// and is read out as selected.
class _MoodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MoodChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      selected: selected,
      child: CupertinoClickable(
        semanticLabel: label,
        onTap: onTap,
        focusRadius: 16,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(color: selected ? t.accentFill : t.fill, borderRadius: BorderRadius.circular(16)),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: t.subheadline.copyWith(color: selected ? t.onAccent : t.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line note with a Retry beside it; the only place Flow reports a failure.
class _InlineNote extends StatelessWidget {
  final String text;
  final bool danger;
  final String actionLabel;
  final VoidCallback? onAction;
  const _InlineNote({required this.text, this.danger = false, required this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Row(
      children: [
        Flexible(child: Text(text, style: t.footnote.copyWith(color: danger ? t.danger : t.textSecondary))),
        const SizedBox(width: Space.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: CupertinoClickable(
            semanticLabel: actionLabel,
            onTap: onAction,
            child: Center(
              widthFactor: 1,
              child: Text(actionLabel, style: t.subheadline.copyWith(color: onAction == null ? t.textMuted : t.accent, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the last batch was made of, as a thin bar and a line under it:
/// Familiar (solid) · Fresh (striped) · New language (dotted). Each part has its
/// own pattern as well as its own tone, so they read apart without colour.
/// Read out as one sentence while Flow is active.
class FlowBlendStrip extends StatelessWidget {
  final FlowBlend blend;
  const FlowBlendStrip({super.key, required this.blend});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final parts = [
      ('Familiar', blend.familiar, t.textMuted, _BlendPattern.solid),
      ('Fresh', blend.fresh, t.textSecondary, _BlendPattern.stripes),
      ('New language', blend.explore, t.textPrimary, _BlendPattern.dots),
    ].where((p) => p.$2 > 0).toList();
    return Semantics(
      container: true,
      label: 'Last batch: ${blend.familiar} familiar, ${blend.fresh} fresh, ${blend.explore} in a new language',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    for (final (i, (_, n, color, pattern)) in parts.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(flex: n, child: CustomPaint(painter: _BlendPainter(pattern, color), size: Size.infinite)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              children: [
                for (final (label, n, color, pattern) in parts)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox.square(dimension: 10, child: CustomPaint(painter: _BlendPainter(pattern, color))),
                      ),
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

enum _BlendPattern { solid, stripes, dots }

class _BlendPainter extends CustomPainter {
  final _BlendPattern pattern;
  final Color color;
  const _BlendPainter(this.pattern, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    switch (pattern) {
      case _BlendPattern.solid:
        canvas.drawRect(Offset.zero & size, paint);
      case _BlendPattern.stripes:
        // Thin diagonal bars over a faint ground.
        canvas.drawRect(Offset.zero & size, Paint()..color = color.withValues(alpha: 0.28));
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (var x = -size.height; x < size.width + size.height; x += 5) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
        }
      case _BlendPattern.dots:
        canvas.drawRect(Offset.zero & size, Paint()..color = color.withValues(alpha: 0.28));
        for (var x = 1.5; x < size.width; x += 4) {
          for (var y = 1.5; y < size.height; y += 4) {
            canvas.drawCircle(Offset(x, y), 1.1, paint);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_BlendPainter old) => old.pattern != pattern || old.color != color;
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

/// A small "Flow" mark with its mood for surfaces outside Home (the mini player,
/// the Windows player bar, the sidebar): shown only while Flow feeds the queue,
/// it opens the mood sheet. [compact] drops the words and keeps the glyph.
class FlowActiveBadge extends ConsumerWidget {
  final bool compact;
  const FlowActiveBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(flowProvider.select((s) => s.active));
    if (!active) return const SizedBox.shrink();
    final mood = ref.watch(flowProvider.select((s) => s.mood));
    final t = ThemeTokens.of(context);
    final label = flowLabel(mood);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: CupertinoClickable(
        semanticLabel: '$label. Change mood',
        onTap: () => showFlowMoodSheet(context, ref),
        child: Center(
          widthFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NaviIcon(NaviGlyph.flow, size: 18, color: t.textPrimary),
              if (!compact) ...[
                const SizedBox(width: Space.xs),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textPrimary))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Flow" or "Flow · Chill".
String flowLabel(String? mood) =>
    mood == null || mood.isEmpty ? 'Flow' : 'Flow · ${mood[0].toUpperCase()}${mood.substring(1)}';
