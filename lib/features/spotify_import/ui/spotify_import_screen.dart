import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show confirmDestructive, showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/import_progress_bar.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../exportify_import/data/exportify_models.dart' show groupThousands;
import '../../exportify_import/ui/exportify_fetch_screen.dart';
import '../data/spotify_import_models.dart';
import '../logic/spotify_import_providers.dart';
import '../logic/spotify_parser.dart';

/// Settings › Import › Spotify History. The person picks the ZIP Spotify sent (“Extended streaming history”);
/// it is read on this device, only the needed fields are kept, and those go to the server a page at a time.
/// Songs in the library become plays with real skip information; the rest go on the Wishlist.
class SpotifyImportScreen extends StatelessWidget {
  const SpotifyImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    return LargeTitlePage(
      title: 'Spotify History',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
            child: Text(
              'Bring your Spotify history so Smart Shuffle knows which songs you skip and which you play through. '
              'Ask Spotify for your “Extended streaming history” at spotify.com/account/privacy; it arrives by email '
              'as a ZIP, usually within a few days.',
              style: t.subheadline,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SpotifyPrivacyNote()),
        const SliverToBoxAdapter(child: SpotifyImportPanel()),
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
      ],
    );
  }
}

/// Exactly what is read and what is dropped, said before anything is chosen.
class SpotifyPrivacyNote extends StatelessWidget {
  const SpotifyPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'What is used'),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Read from each song you played', style: t.callout),
              const SizedBox(height: Space.xxs),
              Text(
                'When it played, the title, artist and album, how long you listened, and whether you skipped it or '
                'let it finish.',
                style: t.footnote,
              ),
              const SizedBox(height: Space.md),
              Text('Dropped on this device, never sent', style: t.callout),
              const SizedBox(height: Space.xxs),
              Text(
                'Your IP address, country, device and platform, connection and offline details, podcasts and '
                'audiobooks, video history, and anything you played in a Private Session.',
                style: t.footnote,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SpotifyImportPanel extends ConsumerWidget {
  const SpotifyImportPanel({super.key});

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remove imported history?',
      message:
          'The plays imported from Spotify and the songs they added to your Wishlist are removed. '
          'Songs you already fetched stay.',
      confirmLabel: 'Remove',
    );
    if (!ok || !context.mounted) return;
    final n = await ref.read(spotifyImportProvider.notifier).undo();
    if (n != null && context.mounted) showToast(context, 'Removed ${groupThousands(n)} plays');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    final run = ref.watch(spotifyImportProvider);
    final ctl = ref.read(spotifyImportProvider.notifier);
    final job = run.job;

    if (!run.loaded) return _Skeleton(gutter: gutter);
    if (run.loadFailed && job == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: Space.md, horizontal: gutter - Space.gutter),
        child: InlineError(message: run.error ?? 'Couldn’t reach the server.', onRetry: ctl.load),
      );
    }

    final parsed = run.parsed;
    final resumable = job != null && !job.isDone && job.status != 'cancelled';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: job == null && parsed == null ? 'Import' : 'Your export'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (run.parsing)
                Row(
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(width: Space.md),
                    Expanded(child: Text('Reading your export on this device…', style: t.subheadline)),
                  ],
                )
              else if (parsed != null) ...[
                _ParsedSummary(summary: parsed),
                const SizedBox(height: Space.md),
                TintedButton(
                  glyph: run.running ? NaviGlyph.pause : NaviGlyph.download,
                  label: run.running ? 'Pause' : (run.pagesSent > 0 ? 'Resume' : 'Import ${groupThousands(parsed.kept)} Plays'),
                  filled: !run.running,
                  onTap: run.running ? ctl.pause : ctl.start,
                ),
                if (!run.running)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: ctl.discard,
                    child: Text('Choose a Different File', style: t.subheadline.copyWith(color: t.accent)),
                  ),
              ] else
                TintedButton(
                  glyph: NaviGlyph.doc,
                  label: resumable ? 'Choose the Same File to Resume' : (job?.isDone == true ? 'Import Another File' : 'Choose Export File'),
                  filled: job == null || resumable,
                  onTap: ctl.choose,
                ),
              if (run.error != null && !run.loadFailed)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(run.error!, style: t.footnote.copyWith(color: t.danger)),
                ),
              if (run.running || (parsed != null && run.pagesSent > 0))
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: ImportProgressBar(value: run.sendProgress),
                ),
              if (job != null) _Result(job: job),
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
                onTap: run.running ? null : () => _undo(context, ref),
              ),
            ],
          ),
      ],
    );
  }
}

/// Four-state loading: lines shaped like the summary while the server is asked.
class _Skeleton extends StatelessWidget {
  final double gutter;
  const _Skeleton({required this.gutter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: Space.md),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: double.infinity, height: 44, radius: Radii.thumb),
          SizedBox(height: Space.md),
          SkeletonBox(width: 220, height: 12, radius: Radii.thumb),
          SizedBox(height: Space.sm),
          SkeletonBox(width: 160, height: 12, radius: Radii.thumb),
        ],
      ),
    );
  }
}

/// What the chosen file holds and what was thrown away, before anything is sent.
class _ParsedSummary extends StatelessWidget {
  final SpotifyParseSummary summary;
  const _ParsedSummary({required this.summary});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = summary;
    final lines = <String>[
      '${groupThousands(s.kept)} plays of songs${s.firstTs != null ? ', ${monthYear(s.firstTs!)} to ${monthYear(s.lastTs!)}' : ''}.',
      if (s.dropped > 0)
        'Left out: ${[
          if (s.droppedEpisodes > 0) '${groupThousands(s.droppedEpisodes)} podcast ${s.droppedEpisodes == 1 ? 'episode' : 'episodes'}',
          if (s.droppedAudiobooks > 0) '${groupThousands(s.droppedAudiobooks)} audiobook parts',
          if (s.droppedPrivate > 0) '${groupThousands(s.droppedPrivate)} private ${s.droppedPrivate == 1 ? 'play' : 'plays'}',
          if (s.droppedUnusable > 0) '${groupThousands(s.droppedUnusable)} unreadable rows',
        ].join(', ')}.',
      if (s.filesUnreadable > 0) '${s.filesUnreadable} history ${s.filesUnreadable == 1 ? 'file' : 'files'} couldn’t be read.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.format == SpotifyFormat.extended ? 'Extended streaming history' : 'Basic streaming history', style: t.callout),
        const SizedBox(height: Space.xxs),
        for (final l in lines) Text(l, style: t.footnote),
      ],
    );
  }
}

/// What the server did with the plays.
class _Result extends StatelessWidget {
  final SpotifyJob job;
  const _Result({required this.job});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final range = job.oldestTs != null && job.newestTs != null
        ? ' · ${monthYear(job.oldestTs!)} to ${monthYear(job.newestTs!)}'
        : '';
    final lines = <String>[
      if (job.isDone)
        'Done: ${groupThousands(job.fetched)} plays read$range.'
      else
        'Sent ${groupThousands(job.fetched)}${job.total != null ? ' of ${groupThousands(job.total!)}' : ''} plays.',
      '${groupThousands(job.imported)} added to your taste: ${groupThousands(job.skips)} skips and '
          '${groupThousands(job.listens)} listens counted',
      '${groupThousands(job.songsMatched)} songs found in your library · ${groupThousands(job.songsUnmatched)} on your Wishlist',
      if (job.already > 0) '${groupThousands(job.already)} repeated or imported before',
      if (job.nearDups > 0) '${groupThousands(job.nearDups)} left out: you already played them in the app',
      if (job.unclear > 0) '${groupThousands(job.unclear)} cut-short plays with no clear reason were left out',
      if (job.rejectedTotal > 0) '${groupThousands(job.rejectedTotal)} unusable rows were refused',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Text(l, style: t.footnote)],
      ),
    );
  }
}
