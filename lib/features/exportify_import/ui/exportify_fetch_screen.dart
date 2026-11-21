import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive;
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/exportify_models.dart';
import '../logic/exportify_providers.dart';

/// "Fetch my wishlist": the order, the nightly cap and the disk floor, what it will cost, the
/// progress, the songs that failed, and a way to pause or cancel. The server does the fetching
/// (a little each night, never past the floor); this screen only sets the plan and shows it.
class ExportifyFetchScreen extends ConsumerStatefulWidget {
  final int id;
  const ExportifyFetchScreen({super.key, required this.id});

  @override
  ConsumerState<ExportifyFetchScreen> createState() => _ExportifyFetchScreenState();
}

class _ExportifyFetchScreenState extends ConsumerState<ExportifyFetchScreen> {
  /// The settings on screen. Starts as the server's, then is the user's.
  PlanDraft? _draft;
  String? _problem;

  ExportifyDetail get _detail => ref.read(exportifyDetailProvider(widget.id).notifier);

  Future<void> _run(Future<String?> Function() action) async {
    final problem = await action();
    if (mounted) setState(() => _problem = problem);
  }

  void _change(PlanDraft next, ExportifySummary imp) {
    setState(() => _draft = next);
    // Once a fetch is under way the server holds the plan, so a change is saved at once.
    if (imp.plan.status != PlanStatus.idle) _run(() => _detail.savePlan(next));
  }

  Future<void> _cancel(ExportifySummary imp) async {
    final ok = await confirmDestructive(
      context,
      title: 'Cancel the fetch?',
      message: 'The batch running now is stopped and nothing more is fetched. '
          'The ${groupThousands(imp.waiting + imp.count(WishlistState.queued) + imp.count(WishlistState.failed))} '
          'songs not fetched yet stay on your wishlist.',
      confirmLabel: 'Cancel Fetch',
    );
    if (ok && mounted) await _run(_detail.cancel);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(exportifyDetailProvider(widget.id));
    return LargeTitlePage(
      title: 'Wishlist',
      slivers: [
        ...detail.when(
          loading: () => const [SliverToBoxAdapter(child: _Skeleton())],
          error: (_, _) => [
            SliverToBoxAdapter(
              child: MessageState.error(
                title: 'Couldn’t load your wishlist',
                onRetry: () => ref.invalidate(exportifyDetailProvider(widget.id)),
              ),
            ),
          ],
          data: (imp) {
            final draft = _draft ?? imp.plan.draft;
            if (imp.onWishlist == 0) {
              return const [
                SliverToBoxAdapter(
                  child: MessageState(
                    icon: NaviGlyph.checkCircle,
                    title: 'Nothing to fetch',
                    message: 'Everything on this list is already in your library.',
                  ),
                ),
              ];
            }
            return _body(context, imp, draft);
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }

  List<Widget> _body(BuildContext context, ExportifySummary imp, PlanDraft draft) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    final status = imp.plan.status;
    final failed = imp.count(WishlistState.failed);
    final editable = status != PlanStatus.cancelled;

    return [
      SliverToBoxAdapter(child: _Status(imp: imp)),
      if (imp.hasFetch) SliverToBoxAdapter(child: _Progress(imp: imp)),
      SliverToBoxAdapter(child: _Cost(id: imp.id, draft: draft)),
      if (editable) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Settings')),
        SliverToBoxAdapter(child: _Settings(draft: draft, onChanged: (d) => _change(d, imp))),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.lg, gutter, 0),
          child: _primary(imp, draft),
        ),
      ),
      if (status.running || status == PlanStatus.paused)
        SliverToBoxAdapter(
          child: Center(
            child: CupertinoButton(
              onPressed: () => _cancel(imp),
              child: Text('Cancel Fetch', style: t.subheadline.copyWith(color: t.danger, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      if (_problem != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, Space.sm, gutter, 0),
            child: Text(_problem!, style: t.footnote.copyWith(color: t.danger)),
          ),
        ),
      if (failed > 0) ...[
        SliverToBoxAdapter(child: SectionHeader(title: 'Didn’t come in · ${groupThousands(failed)}')),
        SliverToBoxAdapter(child: _FailedList(id: imp.id, total: failed)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter - Space.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                onPressed: () => _run(_detail.retryFailed),
                child: Text('Try Them Again', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  /// The one primary action for where the fetch stands.
  Widget _primary(ExportifySummary imp, PlanDraft draft) => switch (imp.plan.status) {
        PlanStatus.active || PlanStatus.pausedDisk => TintedButton(
            glyph: NaviGlyph.pause,
            label: 'Pause',
            filled: true,
            onTap: () => _run(_detail.pause),
          ),
        PlanStatus.paused => TintedButton(
            glyph: NaviGlyph.play,
            label: 'Resume',
            filled: true,
            onTap: () => _run(() => _detail.start(draft)),
          ),
        _ => TintedButton(
            glyph: NaviGlyph.download,
            label: imp.plan.status == PlanStatus.idle ? 'Start Fetching' : 'Fetch Again',
            filled: true,
            onTap: () => _run(() => _detail.start(draft)),
          ),
      };
}

/// "Fetching", "Paused: disk is low", … and the server's own note under it.
class _Status extends StatelessWidget {
  final ExportifySummary imp;
  const _Status({required this.imp});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final plan = imp.plan;
    final low = plan.status == PlanStatus.pausedDisk;
    final title = switch (plan.status) {
      PlanStatus.idle => 'Ready to fetch',
      PlanStatus.active => 'Fetching',
      PlanStatus.paused => 'Paused',
      PlanStatus.pausedDisk => 'Paused: disk is low',
      PlanStatus.done => 'Finished',
      PlanStatus.cancelled => 'Cancelled',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (low) ...[NaviIcon(NaviGlyph.alert, size: 20, color: t.textPrimary), const SizedBox(width: Space.sm)],
            Flexible(child: Text(title, style: t.title2)),
          ]),
          if (plan.note != null) ...[const SizedBox(height: Space.xs), Text(plan.note!, style: t.subheadline)],
        ],
      ),
    );
  }
}

/// A bar and the counts: fetched, on its way, didn't come in, still waiting.
class _Progress extends StatelessWidget {
  final ExportifySummary imp;
  const _Progress({required this.imp});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final done = imp.count(WishlistState.downloaded);
    final queued = imp.count(WishlistState.queued);
    final failed = imp.count(WishlistState.failed);
    final total = done + queued + failed + imp.waiting;
    final fraction = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: t.fill)),
                FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: ColoredBox(color: t.accent)),
              ]),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            [
              '${groupThousands(done)} of ${groupThousands(total)} fetched',
              if (queued > 0) '${groupThousands(queued)} on its way',
              if (failed > 0) '${groupThousands(failed)} didn’t come in',
              if (imp.waiting > 0) '${groupThousands(imp.waiting)} waiting',
            ].join(' · '),
            style: t.footnote,
          ),
        ],
      ),
    );
  }
}

/// "These 5,720 songs need about 210 GB (0.51 GB per hour of music); you have 134 GB free."
class _Cost extends ConsumerWidget {
  final int id;
  final PlanDraft draft;
  const _Cost({required this.id, required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final est = ref.watch(exportifyEstimateProvider((id, draft)));
    final gutter = pageGutter(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.sm),
      child: est.when(
        loading: () => const SkeletonBox(width: double.infinity, height: 36),
        error: (_, _) => Text('Couldn’t work out the size. It will be checked again when you start.', style: t.footnote),
        data: (e) {
          if (e.songs == 0) {
            return Text('No songs match these settings. Lower the minimum popularity.', style: t.subheadline);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These ${groupThousands(e.songs)} songs need about ${formatGb(e.gb)} '
                '(${e.gbPerHour} GB per hour of music); you have ${formatGb(e.freeGb)} free.',
                style: t.subheadline.copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: Space.xs),
              Text(
                [
                  if (e.tooBig)
                    'Only ${groupThousands(e.fits)} fit above your ${e.floorGb.round()} GB floor; fetching pauses there.',
                  'About ${e.nights == 1 ? 'one night' : '${groupThousands(e.nights)} nights'} at ${draft.perNight} a night'
                      ' and ${e.botHours < 1 ? 'under an hour' : '${e.botHours.round()} hours'} of bot time.',
                ].join(' '),
                style: t.footnote,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The five settings, as plain rows on the page: order, minimum popularity, songs a night,
/// the disk floor, night only.
class _Settings extends StatelessWidget {
  final PlanDraft draft;
  final ValueChanged<PlanDraft> onChanged;
  const _Settings({required this.draft, required this.onChanged});

  static const _popularity = {0: 'Any', 20: '20+', 30: '30+', 40: '40+', 50: '50+'};
  static const _perNight = {25: '25', 50: '50', 100: '100', 200: '200', 400: '400'};
  static const _floor = {20: '20 GB', 40: '40 GB', 60: '60 GB', 100: '100 GB'};

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    Widget label(String text, [String? hint]) => Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.md, gutter, Space.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(text, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
            if (hint != null) ...[const SizedBox(width: Space.sm), Flexible(child: Text(hint, style: t.footnote))],
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Order'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: NaviSegmented<ExportifyOrder>(
            segments: const {ExportifyOrder.popularity: 'Most popular first', ExportifyOrder.list: 'My list order'},
            value: draft.order,
            onChanged: (v) => onChanged((
              order: v, minPopularity: draft.minPopularity, perNight: draft.perNight, floorGb: draft.floorGb, nightOnly: draft.nightOnly,
            )),
          ),
        ),
        label('Minimum popularity', 'Spotify’s 0–100 score'),
        FilterPills<int>(
          options: _popularity,
          value: _nearest(_popularity.keys, draft.minPopularity),
          onChanged: (v) => onChanged((
            order: draft.order, minPopularity: v, perNight: draft.perNight, floorGb: draft.floorGb, nightOnly: draft.nightOnly,
          )),
        ),
        label('Songs a night'),
        FilterPills<int>(
          options: _perNight,
          value: _nearest(_perNight.keys, draft.perNight),
          onChanged: (v) => onChanged((
            order: draft.order, minPopularity: draft.minPopularity, perNight: v, floorGb: draft.floorGb, nightOnly: draft.nightOnly,
          )),
        ),
        label('Keep free', 'Fetching pauses below this'),
        FilterPills<int>(
          options: _floor,
          value: _nearest(_floor.keys, draft.floorGb),
          onChanged: (v) => onChanged((
            order: draft.order, minPopularity: draft.minPopularity, perNight: draft.perNight, floorGb: v, nightOnly: draft.nightOnly,
          )),
        ),
        GroupedSection(children: [
          GroupedRow(
            title: 'Only at night',
            subtitle: 'Between 1 and 7 am, so the bot is free in the day',
            showChevron: false,
            trailing: CupertinoSwitch(
              value: draft.nightOnly,
              onChanged: (v) => onChanged((
                order: draft.order, minPopularity: draft.minPopularity, perNight: draft.perNight, floorGb: draft.floorGb, nightOnly: v,
              )),
            ),
          ),
        ]),
      ],
    );
  }

  /// A saved value that isn't one of the pills (set elsewhere) lights the closest one.
  static int _nearest(Iterable<int> keys, int v) =>
      keys.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
}

class _FailedList extends ConsumerWidget {
  final int id;
  final int total;
  const _FailedList({required this.id, required this.total});

  static const _shown = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final songs = ref.watch(exportifyFailedProvider(id));
    return songs.when(
      loading: () => const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CupertinoActivityIndicator())),
      error: (_, _) => MessageState.error(
        title: 'Couldn’t load the list',
        onRetry: () => ref.invalidate(exportifyFailedProvider(id)),
      ),
      data: (list) => Column(
        children: [
          GroupedSection(children: [
            for (final s in list.take(_shown))
              GroupedRow(
                title: s.title,
                subtitle: [if (s.artist.isNotEmpty) s.artist, if (s.error != null) s.error!].join(' · '),
                showChevron: false,
              ),
          ]),
          if (total > _shown)
            Padding(
              padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('and ${groupThousands(total - _shown)} more', style: t.footnote),
              ),
            ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 180, height: 24),
          SizedBox(height: Space.lg),
          SkeletonBox(width: double.infinity, height: 44),
          SizedBox(height: Space.md),
          SkeletonBox(width: double.infinity, height: 120),
        ],
      ),
    );
  }
}
