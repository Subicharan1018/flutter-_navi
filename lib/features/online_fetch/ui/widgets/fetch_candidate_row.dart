import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/cover_art.dart';
import '../../data/fetch_models.dart';
import '../../logic/online_fetch_providers.dart';

/// One online result — a song (title, artist · album, what kind of recording
/// it is), an album or playlist (with its song count), or an artist — and,
/// once picked, where its download is. Watches only its own download.
class FetchCandidateRow extends ConsumerWidget {
  final FetchCandidate candidate;
  final bool showSeparator;

  /// Tapped a song or album that isn't in the library yet (or whose download
  /// failed); for an artist, opens their top songs.
  final VoidCallback onDownload;

  /// Tapped a song that's already in the library.
  final VoidCallback onPlayOwned;

  /// Non-null while picking several songs: whether this one is picked.
  /// Tapping then toggles it ([onDownload] is called).
  final bool? selected;

  /// False for a pasted link's songs: they download together, so a row only
  /// shows whether the song is owned and, once started, its progress.
  final bool interactive;

  /// The best match, set larger than the rest: a 64 pt cover and a title3 title.
  final bool featured;

  const FetchCandidateRow({
    super.key,
    required this.candidate,
    required this.onDownload,
    required this.onPlayOwned,
    this.showSeparator = true,
    this.selected,
    this.interactive = true,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final c = candidate;
    final song = c.isSong;
    final job = song ? ref.watch(fetchJobsProvider.select((d) => d.jobFor(c.id))) : null;
    final batch = song ? null : ref.watch(fetchJobsProvider.select((d) => d.batchFor(c.id)));
    final status = song ? _songStatus(job, c) : (batch == null ? null : fetchBatchStatus(batch));
    final selecting = selected != null;
    final tappable = fetchCandidateTappable(c, job: job, batch: batch, selecting: selecting, interactive: interactive);
    final art = featured ? 64.0 : 44.0;

    return Semantics(
      button: tappable,
      selected: selected,
      label: [c.title, _subtitle(c), ?status].where((s) => s.isNotEmpty).join(', '),
      hint: !tappable
          ? null
          : selecting
              ? (selected! ? 'Double tap to deselect' : 'Double tap to select')
              : song
                  ? (c.inLibrary ? 'Double tap to play' : 'Double tap to download')
                  : (c.type == FetchSearchType.artist || c.type == FetchSearchType.label)
                      ? 'Double tap to see their songs'
                      : 'Double tap to download',
      excludeSemantics: true,
      child: InkWell(
        onTap: !tappable ? null : (song && c.inLibrary && !selecting ? onPlayOwned : onDownload),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (selecting) ...[
                    NaviIcon(
                      selected! ? NaviGlyph.checkCircle : NaviGlyph.ring,
                      filled: selected!,
                      size: 24,
                      color: !tappable ? t.textMuted : (selected! ? t.accent : t.textSecondary),
                    ),
                    const SizedBox(width: Space.md),
                  ],
                  // A label the bot has no logo for gets a generated cover, so
                  // the list isn't a column of identical placeholders.
                  if (c.type == FetchSearchType.label && (c.coverUrl == null || c.coverUrl!.isEmpty))
                    SizedBox(
                      key: const ValueKey('label-generated-cover'),
                      width: art,
                      height: art,
                      child: GeneratedCover(name: c.title, borderRadius: Radii.thumb),
                    )
                  else
                    CoverArt(
                      url: c.coverUrl,
                      size: art,
                      radius: Radii.thumb,
                      circular: c.type == FetchSearchType.artist,
                      placeholderIcon: switch (c.type) {
                        FetchSearchType.artist => NaviGlyph.person,
                        FetchSearchType.playlist => NaviGlyph.playlist,
                        FetchSearchType.album => NaviGlyph.library,
                        FetchSearchType.label => NaviGlyph.library,
                        FetchSearchType.song => NaviGlyph.note,
                      },
                    ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            maxLines: featured ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: featured ? t.title3 : t.body),
                        const SizedBox(height: 2),
                        Text(_subtitle(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                        // A pasted YouTube list: the original title, so a wrong reading shows.
                        if (c.sourceTitle != null && c.sourceTitle!.isNotEmpty && c.sourceTitle != c.title) ...[
                          const SizedBox(height: 2),
                          Text(c.sourceTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textMuted)),
                        ],
                        if (status != null || (song && c.kind.label != null)) ...[
                          const SizedBox(height: 2),
                          Text(
                            status ?? c.kind.label!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote.copyWith(color: _statusColor(t, job, batch, c)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!selecting) ...[
                    const SizedBox(width: Space.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      child: Center(
                        widthFactor: 1,
                        child: switch (c.type) {
                          _ when !interactive && job == null => c.inLibrary
                              ? NaviIcon(NaviGlyph.checkCircle, size: 22, color: t.textMuted)
                              : const SizedBox.shrink(),
                          FetchSearchType.song => FetchJobIndicator(job: job, inLibrary: c.inLibrary, blocked: c.blocked, pill: true),
                          FetchSearchType.artist || FetchSearchType.label => NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
                          _ => FetchBatchIndicator(batch: batch, pill: true),
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Space.sm),
              if (showSeparator)
                Padding(
                  padding: EdgeInsets.only(left: art + Space.md + (selecting ? 24 + Space.md : 0)),
                  child: Container(height: 0.5, color: t.outline),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The same words and colours the phone row uses, for the Windows table row.
  static String subtitleOf(FetchCandidate c) => _subtitle(c);
  static String? statusOf(FetchJob? job, FetchCandidate c) => _songStatus(job, c);
  static Color statusColorOf(AppThemeTokens t, FetchJob? job, FetchBatch? batch, FetchCandidate c) => _statusColor(t, job, batch, c);

  static String _subtitle(FetchCandidate c) {
    String songs(int n) => n == 1 ? '1 song' : '$n songs';
    return switch (c.type) {
      FetchSearchType.song => [c.artist, c.album].where((s) => s.isNotEmpty).join(' · '),
      FetchSearchType.artist => 'Artist',
      FetchSearchType.label => ['Label', if (c.trackCount != null) songs(c.trackCount!)].join(' · '),
      FetchSearchType.album => ['Album', c.artist, if (c.trackCount != null) songs(c.trackCount!)]
          .where((s) => s.isNotEmpty)
          .join(' · '),
      FetchSearchType.playlist => ['Playlist', if (c.artist.isNotEmpty) 'by ${c.artist}', if (c.trackCount != null) songs(c.trackCount!)]
          .join(' · '),
    };
  }

  static String? _songStatus(FetchJob? job, FetchCandidate c) {
    if (c.unreadable) return 'Couldn’t read this title';
    if (job == null) {
      if (c.inLibrary) return 'In your library';
      if (c.blocked) return kBlockedByAuthor;
      return c.otherVersion ? 'Other version in your library · Download this version' : null;
    }
    return fetchJobStatus(job);
  }

  static Color _statusColor(AppThemeTokens t, FetchJob? job, FetchBatch? batch, FetchCandidate c) {
    if (batch != null) {
      return switch (batch.status) {
        FetchBatchStatus.done => t.positive,
        FetchBatchStatus.failed => t.danger,
        _ => t.textMuted,
      };
    }
    return switch (job?.phase) {
      FetchJobPhase.ready => t.positive,
      FetchJobPhase.rejected || FetchJobPhase.failed => t.danger,
      // Blocked is not an error: nothing went wrong and nothing can be done.
      FetchJobPhase.blocked => t.textSecondary,
      null when c.blocked && !c.inLibrary => t.textSecondary,
      // "Cover", "Remix"…: information, so secondary text, not a warning hue.
      null when c.kind != FetchKind.original && !c.inLibrary => t.textSecondary,
      _ => t.textMuted,
    };
  }
}

/// Whether a result can be acted on right now (one rule for the phone row and
/// the Windows table row).
bool fetchCandidateTappable(
  FetchCandidate c, {
  required FetchJob? job,
  required FetchBatch? batch,
  required bool selecting,
  bool interactive = true,
}) =>
    switch (c.type) {
      _ when !interactive || c.unreadable => false,
      // A blocked song has no Retry: the bot can't send it. (Search again is offered by the results.)
      FetchSearchType.song when !c.inLibrary && (c.blocked || job?.phase == FetchJobPhase.blocked) => false,
      _ when selecting => !c.inLibrary && (job == null || job.phase == FetchJobPhase.failed),
      FetchSearchType.song => c.inLibrary || job == null || job.phase == FetchJobPhase.failed,
      FetchSearchType.artist || FetchSearchType.label => true,
      _ => batch == null || batch.status == FetchBatchStatus.failed,
    };

/// Where a download is, in the user's words — shared by the result rows and
/// the downloads lists.
String fetchJobStatus(FetchJob job) => switch (job.phase) {
      FetchJobPhase.preparing => 'Preparing…',
      FetchJobPhase.downloading => 'Downloading ${(job.progress * 100).round()}%',
      FetchJobPhase.adding => 'Adding to your library…',
      FetchJobPhase.ready => 'Added to your library',
      FetchJobPhase.duplicate => 'Already in your library',
      FetchJobPhase.rejected => 'Not available in lossless quality',
      FetchJobPhase.blocked => kBlockedByAuthor,
      FetchJobPhase.failed => job.error ?? 'Download didn’t finish. Tap to try again.',
    };

/// Where a batch is: "Getting the songs…", "23 of 80 songs", or its summary.
String fetchBatchStatus(FetchBatch b) => switch (b.status) {
      FetchBatchStatus.starting => 'Getting the songs…',
      FetchBatchStatus.running => '${b.handled} of ${b.total} songs',
      FetchBatchStatus.done => b.summary,
      FetchBatchStatus.failed => b.error ?? 'Download didn’t finish. Tap to try again.',
    };

/// A download's state as a 24 pt glyph: spinner, progress ring, check or
/// warning. With no job yet: the action the row offers (download, or play
/// when the song is already in the library).
class FetchJobIndicator extends StatelessWidget {
  final FetchJob? job;
  final bool inLibrary;

  /// The bot already refused this song (no job yet): no download glyph.
  final bool blocked;

  /// Result rows: the idle, owned and failed states are words in a capsule
  /// ("Get", "Play", "Retry") like Apple's Get button, not a bare glyph.
  final bool pill;
  const FetchJobIndicator({super.key, required this.job, this.inLibrary = false, this.blocked = false, this.pill = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final j = job;
    if (j == null && blocked && !inLibrary) {
      return NaviIcon(NaviGlyph.close, size: 22, color: t.textMuted);
    }
    if (j == null) {
      if (pill) return inLibrary ? const FetchPill('Play', quiet: true) : const FetchPill('Get');
      return NaviIcon(
        inLibrary ? NaviGlyph.playCircle : NaviGlyph.downloadCircle,
        size: 24,
        color: t.accent,
      );
    }
    if (pill && j.phase == FetchJobPhase.failed) return const FetchPill('Retry', danger: true);
    return switch (j.phase) {
      FetchJobPhase.preparing || FetchJobPhase.adding => const CupertinoActivityIndicator(),
      FetchJobPhase.downloading => _Ring(value: j.progress == 0 ? null : j.progress),
      FetchJobPhase.ready || FetchJobPhase.duplicate =>
        NaviIcon(NaviGlyph.checkCircle, size: 24, color: t.positive, filled: true),
      FetchJobPhase.rejected || FetchJobPhase.failed =>
        NaviIcon(NaviGlyph.alert, size: 24, color: t.danger),
      FetchJobPhase.blocked => NaviIcon(NaviGlyph.close, size: 22, color: t.textMuted),
    };
  }
}

/// [FetchJobIndicator] for an album / playlist: download glyph, overall
/// progress ring, check or warning.
class FetchBatchIndicator extends StatelessWidget {
  final FetchBatch? batch;
  final bool pill;
  const FetchBatchIndicator({super.key, required this.batch, this.pill = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final b = batch;
    if (pill && b?.status == FetchBatchStatus.failed) return const FetchPill('Retry', danger: true);
    return switch (b?.status) {
      null => pill ? const FetchPill('Get') : NaviIcon(NaviGlyph.downloadCircle, size: 24, color: t.accent),
      FetchBatchStatus.starting => const CupertinoActivityIndicator(),
      FetchBatchStatus.running => _Ring(value: b!.progress == 0 ? null : b.progress),
      FetchBatchStatus.done => NaviIcon(NaviGlyph.checkCircle, size: 24, color: t.positive, filled: true),
      FetchBatchStatus.failed => NaviIcon(NaviGlyph.alert, size: 24, color: t.danger),
    };
  }
}

/// The word a result's tap does, in a capsule: "Get" (white on a fill), "Play"
/// for what's already owned (quiet), "Retry" for a failure (red). Only a label:
/// the row around it takes the tap.
class FetchPill extends StatelessWidget {
  final String label;
  final bool quiet;
  final bool danger;
  const FetchPill(this.label, {super.key, this.quiet = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = danger ? t.danger : (quiet ? t.textSecondary : t.onAccent);
    final bg = danger || quiet ? t.fill : t.accentFill;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.capsule)),
      child: Text(label, style: t.footnote.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _Ring extends StatelessWidget {
  final double? value;
  const _Ring({required this.value});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(value: value, strokeWidth: 2.5, color: t.accent, backgroundColor: t.fill),
    );
  }
}
