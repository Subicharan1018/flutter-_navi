import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive, showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../exportify_import/data/exportify_models.dart' show groupThousands;
import '../../exportify_import/ui/exportify_fetch_screen.dart';
import '../data/history_import_models.dart';
import '../logic/history_import_providers.dart';

/// Settings › Import › Listening History. Reads the person's past ListenBrainz listens or Last.fm
/// scrobbles a page at a time (the server keeps the place, so it can be closed and resumed), adds the ones
/// found in the library to their taste data, and puts the rest on the Wishlist.
class HistoryImportScreen extends StatelessWidget {
  const HistoryImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    return LargeTitlePage(
      title: 'Listening History',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
            child: Text(
              'Bring your past plays from ListenBrainz or Last.fm so Smart Shuffle and Flow know your taste from day one. '
              'Songs you have count as plays; the ones you don’t go on your Wishlist. Running it again never counts a play twice.',
              style: t.subheadline,
            ),
          ),
        ),
        for (final s in HistorySource.values) SliverToBoxAdapter(child: HistorySourcePanel(source: s)),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}

class HistorySourcePanel extends ConsumerStatefulWidget {
  final HistorySource source;
  const HistorySourcePanel({super.key, required this.source});

  @override
  ConsumerState<HistorySourcePanel> createState() => _HistorySourcePanelState();
}

class _HistorySourcePanelState extends ConsumerState<HistorySourcePanel> {
  late final TextEditingController _account;
  late final TextEditingController _key;

  HistorySource get _source => widget.source;

  @override
  void initState() {
    super.initState();
    final c = ref.read(historyImportProvider(_source).notifier);
    _account = TextEditingController(text: c.savedAccount);
    _key = TextEditingController(text: _source == HistorySource.lastfm ? c.savedKey : '');
  }

  @override
  void dispose() {
    _account.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _undo() async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove imported history?',
      message:
          'The plays imported from ${_source.label} and the songs they added to your Wishlist are removed. '
          'Songs you already fetched stay.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    final n = await ref.read(historyImportProvider(_source).notifier).undo();
    if (n != null && mounted) showToast(context, 'Removed ${groupThousands(n)} plays');
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    final run = ref.watch(historyImportProvider(_source));
    final ctl = ref.read(historyImportProvider(_source).notifier);
    final job = run.job;
    final lastFm = _source == HistorySource.lastfm;
    final resumable = job != null && !job.isDone && job.status != 'cancelled';
    final label = run.running
        ? 'Pause'
        : (resumable ? 'Resume' : (job?.isDone == true ? 'Import New Plays' : 'Start Import'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: _source.label),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: _account,
                placeholder: '${_source.label} username',
                autocorrect: false,
                enableSuggestions: false,
                enabled: !run.running,
                style: t.body,
              ),
              if (lastFm) ...[
                const SizedBox(height: Space.sm),
                CupertinoTextField(
                  controller: _key,
                  placeholder: 'Last.fm API key',
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !run.running,
                  style: t.body,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Get a free key at last.fm/api/account/create. It stays on this device and is only used while importing.',
                  style: t.footnote,
                ),
              ],
              const SizedBox(height: Space.md),
              TintedButton(
                glyph: run.running ? NaviGlyph.pause : NaviGlyph.download,
                label: label,
                filled: !run.running,
                onTap: run.running ? ctl.pause : () => ctl.start(account: _account.text, apiKey: _key.text),
              ),
              if (run.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(run.error!, style: t.footnote.copyWith(color: t.danger)),
                ),
              if (run.waitingS > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    '${_source.label} asked us to slow down. Continuing in ${run.waitingS} s…',
                    style: t.footnote,
                  ),
                ),
              if (job != null) _Progress(job: job, running: run.running),
            ],
          ),
        ),
        if (job != null && job.wishlistId != null && job.songsUnmatched > 0)
          GroupedSection(
            children: [
              GroupedRow(
                title: 'Wishlist',
                subtitle: '${groupThousands(job.songsUnmatched)} songs you played but don’t have',
                icon: NaviGlyph.playlist,
                onTap: () => navigateInApp(context, ExportifyFetchScreen(id: job.wishlistId!), title: 'Wishlist'),
              ),
            ],
          ),
        if (job != null && (job.imported > 0 || job.wished > 0))
          GroupedSection(
            children: [
              GroupedRow(
                title: 'Remove Imported History',
                destructive: true,
                showChevron: false,
                onTap: run.running ? null : _undo,
              ),
            ],
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final HistoryJob job;
  final bool running;
  const _Progress({required this.job, required this.running});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final p = job.progress;
    final lines = <String>[
      if (job.isDone)
        'Done: ${groupThousands(job.fetched)} plays read${job.incremental ? ' (new ones only)' : ''}.'
      else
        'Read ${groupThousands(job.fetched)}${job.total != null ? ' of ${groupThousands(job.total!)}' : ''} plays.',
      '${groupThousands(job.imported)} added to your taste · ${groupThousands(job.wished)} of songs you don’t have',
      if (job.already > 0) '${groupThousands(job.already)} already imported before',
      if (job.nearDups > 0) '${groupThousands(job.nearDups)} left out: you already played them in the app',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!job.isDone && (running || p != null))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: t.outline)),
                      FractionallySizedBox(
                        widthFactor: p ?? 0.02,
                        child: ColoredBox(color: t.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          for (final l in lines) Text(l, style: t.footnote),
        ],
      ),
    );
  }
}
