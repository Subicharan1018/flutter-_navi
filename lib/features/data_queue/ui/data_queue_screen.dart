import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../exportify_import/data/exportify_models.dart' show groupThousands;
import '../data/data_queue_models.dart';
import '../logic/data_queue_providers.dart';

/// Admin only: the hidden weekly data queue. Songs that reached the library without real Spotify audio
/// features wait here; once a week the admin downloads the next batch of 200, moves it to Spotify with a
/// transfer service, exports it with Exportify and uploads that CSV. Not a playlist, not visible to anyone else.
class DataQueueScreen extends ConsumerWidget {
  const DataQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(dataQueueAdminProvider);
    final status = admin ? ref.watch(dataQueueStatusProvider) : null;
    final gutter = pageGutter(context);

    return LargeTitlePage(
      title: 'Data queue',
      onRefresh: admin
          ? () async {
              ref.invalidate(dataQueueStatusProvider);
              ref.invalidate(dataQueueHistoryProvider);
            }
          : null,
      slivers: [
        if (!admin)
          const SliverToBoxAdapter(
            child: MessageState(
              icon: NaviGlyph.lock,
              title: 'Only for the admin',
              message: 'Sign in with the admin account to see the data queue.',
            ),
          )
        else
          ...status!.when(
            loading: () => const [SliverToBoxAdapter(child: _Skeleton())],
            error: (_, _) => [
              SliverToBoxAdapter(
                child: MessageState.error(
                  title: 'Couldn’t load the data queue',
                  onRetry: () => ref.invalidate(dataQueueStatusProvider),
                ),
              ),
            ],
            data: (s) => [
              SliverToBoxAdapter(child: _Summary(status: s)),
              SliverToBoxAdapter(child: _Batch(status: s)),
              const SliverToBoxAdapter(child: _ActionFeedback()),
              SliverToBoxAdapter(child: _Links(links: s.links)),
              SliverToBoxAdapter(child: _Coverage(coverage: s.coverage)),
              SliverToBoxAdapter(child: _Quality(status: s)),
              const SliverToBoxAdapter(child: _History()),
            ],
          ),
        SliverToBoxAdapter(child: SizedBox(height: Space.xxl, width: gutter)),
      ],
    );
  }
}

/// "3 days ago" / "today".
String ago(DateTime at, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(at).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

class _Summary extends StatelessWidget {
  final QueueStatus status;
  const _Summary({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = status;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(groupThousands(s.waiting), style: t.largeTitle),
          Text(
            s.waiting == 1 ? 'song waiting for Spotify’s numbers' : 'songs waiting for Spotify’s numbers',
            style: t.subheadline,
          ),
          if (s.fullBatchReady) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                NaviIcon(NaviGlyph.bell, size: 18, color: t.textPrimary),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'A full batch of ${s.batchSize} is ready for this week.',
                    style: t.callout.copyWith(color: t.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Batch extends ConsumerWidget {
  final QueueStatus status;
  const _Batch({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final busy = ref.watch(dataQueueActionsProvider.select((a) => a.busy != null));
    final actions = ref.read(dataQueueActionsProvider.notifier);
    final gutter = pageGutter(context);
    final open = status.openBatch;

    if (open == null) {
      final n = status.next;
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, Space.xxl, gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Next batch', style: t.title2),
            const SizedBox(height: Space.xs),
            Text(
              n.size == 0
                  ? 'Nothing is waiting. Songs arrive here when they are added to the library without Spotify data.'
                  : '${groupThousands(n.size)} songs, ${groupThousands(n.withIsrc)} with an ISRC. Most played and newest first.',
              style: t.subheadline,
            ),
            const SizedBox(height: Space.lg),
            TintedButton(
              glyph: NaviGlyph.plus,
              label: 'Make this week’s batch',
              filled: true,
              onTap: busy || n.size == 0 ? null : actions.makeBatch,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, Space.xxl, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week’s batch', style: t.title2),
          const SizedBox(height: Space.xs),
          Text(
            'Batch ${open.id} · ${groupThousands(open.size)} songs · made ${ago(open.createdAt)}',
            style: t.subheadline,
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              TintedButton(
                glyph: NaviGlyph.download,
                label: 'Download CSV',
                onTap: busy ? null : () => actions.download(open.id, 'csv'),
              ),
              TintedButton(
                glyph: NaviGlyph.download,
                label: 'Download TXT',
                onTap: busy ? null : () => actions.download(open.id, 'txt'),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TintedButton(
            glyph: NaviGlyph.doc,
            label: 'Upload Exportify CSV',
            filled: true,
            onTap: busy ? null : () => actions.upload(open.id),
          ),
          const SizedBox(height: Space.md),
          Text(
            '1  Download the file.   2  Upload it at Soundiiz or TuneMyMusic to make a Spotify playlist '
            '(the free tier takes one playlist of up to 200 songs).   3  Export that playlist at exportify.net.   '
            '4  Upload the Exportify CSV here.',
            style: t.footnote,
          ),
          const SizedBox(height: Space.sm),
          CupertinoClickable(
            onTap: busy ? null : () => actions.release(open.id),
            semanticLabel: 'Release this batch',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Text('Release this batch', style: t.subheadline.copyWith(color: t.danger)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Busy line, error, notice and the newest upload's result.
class _ActionFeedback extends ConsumerWidget {
  const _ActionFeedback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final a = ref.watch(dataQueueActionsProvider);
    final gutter = pageGutter(context);
    final r = a.result;
    final feedback = Padding(
      padding: EdgeInsets.fromLTRB(gutter, Space.md, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (a.busy != null)
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: Space.md),
                  Flexible(child: Text(a.busy!, style: t.subheadline, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          if (a.error != null) Text(a.error!, style: t.footnote.copyWith(color: t.danger)),
          if (a.notice != null) Text(a.notice!, style: t.footnote),
        ],
      ),
    );
    if (r == null) return feedback;
    return Column(children: [feedback, const SizedBox(height: Space.sm), _ResultCard(result: r)]);
  }
}

class _ResultCard extends StatelessWidget {
  final UploadSummary result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return GroupedSection(
      header: r.repeated ? 'Already uploaded: nothing changed' : 'Batch ${r.batchId} applied',
      footer: r.onSpotifyWithoutFeatures > 0
          ? '${r.onSpotifyWithoutFeatures} songs are on Spotify but came without audio features.'
          : null,
      children: [
        GroupedRow(title: 'Matched on Spotify', value: groupThousands(r.matched), showChevron: false),
        GroupedRow(title: 'Not found on Spotify', value: groupThousands(r.notFound), showChevron: false),
        GroupedRow(title: 'Spotify features stored', value: groupThousands(r.featuresStored), showChevron: false),
        GroupedRow(title: 'Predicted instead', value: groupThousands(r.predicted), showChevron: false),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  final Map<String, String> links;
  const _Links({required this.links});

  static const _names = {'soundiiz': 'Soundiiz', 'tunemymusic': 'TuneMyMusic'};

  @override
  Widget build(BuildContext context) {
    final rows = [for (final e in links.entries) if (_names.containsKey(e.key)) e];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: GroupedSection(
        header: 'Transfer to Spotify',
        footer: 'Tap a row to copy its link, then open it in a browser.',
        children: [
          for (final e in rows)
            GroupedRow(
              title: _names[e.key]!,
              subtitle: Uri.tryParse(e.value)?.host ?? e.value,
              icon: NaviGlyph.link,
              trailing: const NaviIcon(NaviGlyph.copy, size: 18),
              showChevron: false,
              onTap: () => Clipboard.setData(ClipboardData(text: e.value)),
            ),
        ],
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  final QueueCoverage coverage;
  const _Coverage({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final c = coverage;
    String pct(int n) => '${(c.share(n) * 100).round()}%';
    final gutter = pageGutter(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Library coverage'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: _ShareBar(coverage: c),
        ),
        const SizedBox(height: Space.md),
        GroupedSection(
          footer: 'Real = Spotify’s own numbers. Predicted = guessed from the audio, kept apart and never mixed in.',
          children: [
            GroupedRow(title: 'Real Spotify features', value: '${groupThousands(c.real)} · ${pct(c.real)}', showChevron: false),
            GroupedRow(title: 'Predicted', value: '${groupThousands(c.predicted)} · ${pct(c.predicted)}', showChevron: false),
            GroupedRow(title: 'No data yet', value: '${groupThousands(c.none)} · ${pct(c.none)}', showChevron: false),
          ],
        ),
      ],
    );
  }
}

/// One thin bar: real (white), predicted (secondary), none (the empty track).
class _ShareBar extends StatelessWidget {
  final QueueCoverage coverage;
  const _ShareBar({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final c = coverage;
    int flex(int n) => c.total <= 0 ? 0 : (n * 1000 / c.total).round();
    final none = c.total <= 0 ? 1 : flex(c.none);
    return Semantics(
      label: 'Real ${c.real}, predicted ${c.predicted}, none ${c.none} of ${c.total} songs',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.capsule),
        child: SizedBox(
          height: 8,
          child: Row(
            children: [
              if (flex(c.real) > 0) Expanded(flex: flex(c.real), child: ColoredBox(color: t.textPrimary, child: const SizedBox.expand())),
              if (flex(c.predicted) > 0) Expanded(flex: flex(c.predicted), child: ColoredBox(color: t.textMuted, child: const SizedBox.expand())),
              if (none > 0) Expanded(flex: none, child: ColoredBox(color: t.fill, child: const SizedBox.expand())),
            ],
          ),
        ),
      ),
    );
  }
}

class _Quality extends StatelessWidget {
  final QueueStatus status;
  const _Quality({required this.status});

  static const _sources = {
    'request': 'Requests',
    'youtube': 'YouTube lists',
    'link': 'Playlist links',
    'exportify': 'Exportify imports',
    'backfill': 'Existing library',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final s = status;
    final rows = [
      for (final e in s.waitingBySource.entries)
        GroupedRow(title: _sources[e.key] ?? e.key, value: groupThousands(e.value), showChevron: false),
      if (s.oldestWaitingDays != null)
        GroupedRow(title: 'Oldest waiting', value: '${s.oldestWaitingDays!.round()} days', showChevron: false),
      if (s.matchRate != null)
        GroupedRow(title: 'Found on Spotify', value: '${(s.matchRate! * 100).round()}%', showChevron: false),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: GroupedSection(header: 'Waiting by source', children: rows),
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(dataQueueHistoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Past batches'),
        history.when(
          loading: () => const _Skeleton(rows: 2),
          error: (_, _) => MessageState.error(
            title: 'Couldn’t load the history',
            onRetry: () => ref.invalidate(dataQueueHistoryProvider),
          ),
          data: (list) => list.isEmpty
              ? const MessageState(
                  icon: NaviGlyph.clock,
                  title: 'No batches yet',
                  message: 'Make the first batch when 200 songs are waiting.',
                )
              : GroupedSection(children: [
                  for (final b in list)
                    GroupedRow(
                      title: 'Batch ${b.id} · ${_stateLabel(b.state)}',
                      subtitle: '${groupThousands(b.size)} songs · ${ago(b.createdAt)}',
                      value: b.summary == null ? null : '${b.summary!.matched} matched',
                      showChevron: false,
                    ),
                ]),
        ),
      ],
    );
  }
}

String _stateLabel(String s) => switch (s) {
      'open' => 'waiting for upload',
      'closed' => 'done',
      'released' => 'released',
      _ => s,
    };

class _Skeleton extends StatelessWidget {
  final int rows;
  const _Skeleton({this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context), vertical: Space.sm),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.sm),
              child: SkeletonBox(width: double.infinity, height: 40),
            ),
        ],
      ),
    );
  }
}
