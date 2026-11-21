import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast, showToastWithAction;
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart' show TintedButton;
import '../../../widgets/ui/states.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../data/weekly_models.dart';
import '../logic/preview_player.dart';
import '../logic/weekly_providers.dart';

/// Widest the page gets on a desktop window: a list this wide reads as a list, not a table.
const double kWeeklyMaxWidth = 720;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "2026-11-16" → "16 Nov". Empty when it is not a date.
String weekOfLabel(String week) {
  final d = DateTime.tryParse(week);
  return d == null ? '' : _day(d);
}

String _say(Object e) => e is OnlineFetchException ? e.message : 'That didn’t work. Check your connection and try again.';

/// Weekly Exploration: the week's new songs, a 30 s preview each, Keep or Not for me.
/// What the picking rule is: docs/weekly-exploration.md.
class WeeklyExplorationScreen extends ConsumerWidget {
  const WeeklyExplorationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklyExplorationProvider);
    return LargeTitlePage(
      title: 'Weekly Exploration',
      onRefresh: () => ref.read(weeklyExplorationProvider.notifier).refresh(),
      slivers: [
        SliverToBoxAdapter(
          child: _Centered(
            child: async.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(padding: EdgeInsets.only(top: Space.sm), child: TrackListSkeleton(rows: 8)),
              error: (e, _) => MessageState.error(
                title: 'Your list didn’t load',
                message: _say(e),
                onRetry: () => ref.invalidate(weeklyExplorationProvider),
              ),
              data: (w) => _Body(w),
            ),
          ),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kWeeklyMaxWidth), child: child),
      );
}

class _Body extends ConsumerWidget {
  final WeeklyExploration w;
  const _Body(this.w);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!w.enabled) {
      return MessageState(
        icon: NaviGlyph.explore,
        title: 'Weekly Exploration is off',
        message: 'Turn it on and each week brings about twenty songs you haven’t heard, picked from what you play.',
        actionLabel: 'Turn on',
        onAction: () async {
          try {
            await ref.read(weeklyExplorationProvider.notifier).setEnabled(true);
          } catch (e) {
            if (context.mounted) showToast(context, _say(e));
          }
        },
      );
    }
    if (w.picks.isEmpty) {
      return w.building
          ? const MessageState(
              art: EmptyArtKind.record,
              title: 'Finding songs for you',
              message: 'This takes about a minute the first time each week. You can leave this page; it will be ready.',
            )
          : MessageState(
              art: EmptyArtKind.record,
              title: 'Nothing new yet',
              message: w.buildNote ?? 'Play a few songs and your first list is made on the next visit.',
            );
    }
    final undecided = [for (final p in w.picks) if (p.isPending || p.state == PickState.skipped) p];
    final kept = w.kept;
    final thisWeek = [for (final p in undecided) if (p.week == w.week) p];
    final earlier = [for (final p in undecided) if (p.week != w.week) p];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(w),
        if (thisWeek.isNotEmpty) ...[
          _SectionLabel(w.week.isEmpty ? 'To decide' : 'New this week'),
          for (final p in thisWeek) _PickRow(key: ValueKey('pick-${p.id}'), pick: p, night: w),
        ],
        if (earlier.isNotEmpty) ...[
          const _SectionLabel('Still here from last week'),
          for (final p in earlier) _PickRow(key: ValueKey('pick-${p.id}'), pick: p, night: w),
        ],
        if (kept.isNotEmpty) ...[
          const _SectionLabel('Kept'),
          for (final p in kept) _PickRow(key: ValueKey('pick-${p.id}'), pick: p, night: w),
        ],
        _Footer(w),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: the week as a row of ticks
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final WeeklyExploration w;
  const _Header(this.w);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final pending = w.pending;
    final passed = w.picks.where((p) => p.state == PickState.skipped).length;
    final soon = [for (final p in pending) ?p.expiresAt].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final playing = ref.watch(previewControllerProvider.select((s) => s.status != PreviewStatus.idle));
    final any = pending.any((p) => p.previewUrl != null);
    final week = weekOfLabel(w.week);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (week.isNotEmpty) Text('Week of $week', style: t.headline),
          const SizedBox(height: Space.xs),
          Text(
            [
              if (pending.isNotEmpty) '${pending.length} to hear',
              if (w.kept.isNotEmpty) '${w.kept.length} kept',
              if (passed > 0) '$passed passed',
            ].join(' · '),
            style: t.subheadline,
          ),
          const SizedBox(height: Space.lg),
          _Ledger(picks: w.picks),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              TintedButton(
                filled: true,
                glyph: playing ? NaviGlyph.pause : NaviGlyph.play,
                label: playing ? 'Stop previews' : 'Play previews',
                onTap: !playing && !any
                    ? null
                    : () {
                        final c = ref.read(previewControllerProvider.notifier);
                        playing ? c.stop() : c.playAll();
                      },
              ),
            ],
          ),
          if (soon != null) ...[
            const SizedBox(height: Space.md),
            Text('Songs you leave alone go on ${_day(soon)}.', style: t.footnote.copyWith(color: t.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// The week as ticks, one per song: waiting (a short tick), kept (tall and white), passed (a dot),
/// and the song playing now stands out like a playhead. The page's signature.
class _Ledger extends ConsumerWidget {
  final List<WeeklyPick> picks;
  const _Ledger({required this.picks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final current = ref.watch(previewControllerProvider.select((s) => s.status == PreviewStatus.idle ? null : s.pickId));
    final at = current == null ? -1 : picks.indexWhere((p) => p.id == current);
    return Semantics(
      label: 'The week: ${picks.length} songs',
      child: SizedBox(
        height: 28,
        width: double.infinity,
        child: CustomPaint(
          painter: LedgerPainter(
            marks: [for (final p in picks) p.isKept ? LedgerMark.kept : (p.state == PickState.skipped ? LedgerMark.passed : LedgerMark.waiting)],
            playing: at,
            ink: t.textPrimary,
            dim: t.textMuted,
          ),
        ),
      ),
    );
  }
}

enum LedgerMark { waiting, kept, passed }

class LedgerPainter extends CustomPainter {
  final List<LedgerMark> marks;
  final int playing;
  final Color ink;
  final Color dim;
  const LedgerPainter({required this.marks, required this.playing, required this.ink, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    if (marks.isEmpty) return;
    final n = marks.length;
    final slot = size.width / n;
    final base = size.height;
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.min(2.5, slot * 0.34);
    for (var i = 0; i < n; i++) {
      final x = slot * (i + 0.5);
      final (h, c) = switch (marks[i]) {
        LedgerMark.kept => (26.0, ink),
        LedgerMark.waiting => (14.0, dim.withValues(alpha: 0.8)),
        LedgerMark.passed => (4.0, dim.withValues(alpha: 0.35)),
      };
      final isNow = i == playing;
      p.color = isNow ? ink : c;
      canvas.drawLine(Offset(x, base), Offset(x, base - (isNow ? math.max(h, 20.0) : h)), p);
    }
  }

  @override
  bool shouldRepaint(LedgerPainter o) => o.playing != playing || o.ink != ink || o.dim != dim || !_same(o.marks, marks);

  static bool _same(List<LedgerMark> a, List<LedgerMark> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xs),
      child: Text(text, style: t.title3),
    );
  }
}

class _Footer extends StatelessWidget {
  final WeeklyExploration w;
  const _Footer(this.w);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final cap = w.cap == 0 ? 'Downloads are paused (the weekly limit is 0).' : '${w.keptThisWeek} of ${w.cap} downloads used this week.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.huge),
      child: Text(
        'Songs you keep download between ${w.nightFrom} and ${w.nightTo} am, a few at a time. $cap '
        'A preview is the first 30 seconds from Apple Music.',
        style: t.footnote.copyWith(color: t.textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A song
// ─────────────────────────────────────────────────────────────────────────────

class _PickRow extends ConsumerWidget {
  static const double cover = 56;
  final WeeklyPick pick;
  final WeeklyExploration night;
  const _PickRow({super.key, required this.pick, required this.night});

  String _status() => switch (pick.download) {
        DownloadStage.ready => 'In your library',
        DownloadStage.queued => 'Kept · downloads ${night.nightFrom}–${night.nightTo} am',
        DownloadStage.failed => 'Kept · couldn’t be fetched, trying again',
        _ => 'Kept · waiting its turn',
      };

  Future<void> _keep(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(weeklyExplorationProvider.notifier).keep(pick.id);
      await ref.read(previewControllerProvider.notifier).decided(pick.id);
    } catch (e) {
      if (context.mounted) showToast(context, _say(e));
    }
  }

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    final c = ref.read(weeklyExplorationProvider.notifier);
    try {
      await c.skip(pick.id);
      await ref.read(previewControllerProvider.notifier).decided(pick.id);
      if (context.mounted) {
        showToastWithAction(context, 'Not for me. It won’t come back for six months.',
            actionLabel: 'Undo', onAction: () => c.restore(pick.id).catchError((_) {}));
      }
    } catch (e) {
      if (context.mounted) showToast(context, _say(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final desktop = PlatformUtils.isDesktop;
    final subtitle = pick.artist;
    final passed = pick.state == PickState.skipped;
    final line = pick.isKept ? _status() : (pick.previewUrl == null ? '${pick.reason} · no preview' : pick.reason);
    final label = [pick.title, subtitle, line].where((s) => s.isNotEmpty).join(', ');
    return Opacity(
      opacity: passed ? 0.4 : 1,
      child: Semantics(
        container: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.only(left: Space.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: _PreviewCover(pick: pick, size: cover),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: cover + Space.lg),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(pick.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                            if (line.isNotEmpty) ...[
                              const SizedBox(height: Space.xxs),
                              Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textMuted)),
                            ],
                          ],
                        ),
                      ),
                      if (pick.isPending) ..._decide(context, ref, desktop),
                      if (pick.isKept && pick.download == DownloadStage.ready && pick.songId != null)
                        _GlyphButton(
                          glyph: NaviGlyph.playCircle,
                          label: 'Play ${pick.title}',
                          onTap: () async {
                            final ok = await ref.read(weeklyLibraryPlayerProvider)(pick.songId!);
                            if (!ok && context.mounted) showToast(context, 'Couldn’t load this song. Check your connection and try again.');
                          },
                        ),
                      if (pick.isKept && pick.download != DownloadStage.ready) const SizedBox(width: Space.gutter),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _decide(BuildContext context, WidgetRef ref, bool desktop) {
    if (desktop) {
      return [
        TintedButton(label: 'Not for me', height: 32, onTap: () => _skip(context, ref)),
        const SizedBox(width: Space.sm),
        TintedButton(label: 'Keep', filled: true, height: 32, onTap: () => _keep(context, ref)),
        const SizedBox(width: Space.gutter),
      ];
    }
    return [
      _GlyphButton(glyph: NaviGlyph.close, label: 'Not for me: ${pick.title}', onTap: () => _skip(context, ref)),
      _GlyphButton(glyph: NaviGlyph.plusCircle, label: 'Keep ${pick.title}', onTap: () => _keep(context, ref), strong: true),
    ];
  }
}

class _GlyphButton extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool strong;
  const _GlyphButton({required this.glyph, required this.label, required this.onTap, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 44,
        child: Center(child: NaviIcon(glyph, size: strong ? 26 : 20, color: strong ? t.textPrimary : t.textSecondary)),
      ),
    );
  }
}

/// The cover with its preview control: a play button that becomes a 30 s ring while it plays.
class _PreviewCover extends ConsumerWidget {
  final WeeklyPick pick;
  final double size;
  const _PreviewCover({required this.pick, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(previewControllerProvider.select((s) => s.pickId == pick.id ? s.status : PreviewStatus.idle));
    final t = ThemeTokens.of(context);
    final can = pick.previewUrl != null;
    return CupertinoClickable(
      onTap: can ? () => _tap(context, ref) : null,
      semanticLabel: status == PreviewStatus.idle ? 'Preview ${pick.title}' : 'Stop preview of ${pick.title}',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CoverArt(url: pick.coverUrl, size: size, radius: Radii.thumb),
            if (can) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.thumb),
                    color: Colors.black.withValues(alpha: status == PreviewStatus.idle ? 0.28 : 0.55),
                  ),
                ),
              ),
              SizedBox.square(
                dimension: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (status != PreviewStatus.idle) _Ring(color: t.textPrimary, loading: status == PreviewStatus.loading),
                    NaviIcon(status == PreviewStatus.idle ? NaviGlyph.play : NaviGlyph.pause, size: 16, color: Colors.white, filled: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    final c = ref.read(previewControllerProvider.notifier);
    await c.toggle(pick);
    final err = ref.read(previewControllerProvider).error;
    if (err != null && context.mounted) showToast(context, err);
  }
}

/// The ring: 30 seconds all the way round. Only this widget listens to the clock.
class _Ring extends ConsumerWidget {
  final Color color;
  final bool loading;
  const _Ring({required this.color, required this.loading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = loading ? 0.0 : ref.watch(previewProgressProvider);
    return RepaintBoundary(child: CustomPaint(size: const Size.square(34), painter: RingPainter(v, color)));
  }
}

class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const RingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.3);
    canvas.drawArc(r, 0, math.pi * 2, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.25
      ..color = color;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(RingPainter o) => o.progress != progress || o.color != color;
}
