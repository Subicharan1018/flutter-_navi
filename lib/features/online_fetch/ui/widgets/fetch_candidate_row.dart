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

  const FetchCandidateRow({
    super.key,
    required this.candidate,
    required this.onDownload,
    required this.onPlayOwned,
    this.showSeparator = true,
    this.selected,
    this.interactive = true,
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
    final tappable = switch (c.type) {
      _ when !interactive => false,
      _ when selecting => !c.inLibrary && (job == null || job.phase == FetchJobPhase.failed),
      FetchSearchType.song => c.inLibrary || job == null || job.phase == FetchJobPhase.failed,
      FetchSearchType.artist || FetchSearchType.label => true,
      _ => batch == null || batch.status == FetchBatchStatus.failed,
    };
    final art = 44.0;

    return Semantics(
      button: tappable,
      selected: selected,
      label: [c.title, _subtitle(c), ?status].where((s) => s.isNotEmpty).join(', '),
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
                        Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                        const SizedBox(height: 2),
                        Text(_subtitle(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
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
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: switch (c.type) {
                          _ when !interactive && job == null => c.inLibrary
                              ? NaviIcon(NaviGlyph.checkCircle, size: 22, color: t.textMuted)
                              : const SizedBox.shrink(),
                          FetchSearchType.song => FetchJobIndicator(job: job, inLibrary: c.inLibrary),
                          FetchSearchType.artist || FetchSearchType.label => NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
                          _ => FetchBatchIndicator(batch: batch),
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
    if (job == null) {
      if (c.inLibrary) return 'In your library';
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
      // "Cover", "Remix"…: information, so secondary text, not a warning hue.
      null when c.kind != FetchKind.original && !c.inLibrary => t.textSecondary,
      _ => t.textMuted,
    };
  }
}

/// Where a download is, in the user's words — shared by the result rows and
/// the downloads lists.
String fetchJobStatus(FetchJob job) => switch (job.phase) {
      FetchJobPhase.preparing => 'Preparing…',
      FetchJobPhase.downloading => 'Downloading ${(job.progress * 100).round()}%',
      FetchJobPhase.adding => 'Adding to your library…',
      FetchJobPhase.ready => 'Added to your library',
      FetchJobPhase.duplicate => 'Already in your library',
      FetchJobPhase.rejected => 'Not available in lossless quality',
      FetchJobPhase.failed => job.error ?? 'Download didn’t finish. Tap to try again.',
    };

/// Where a batch is: "Getting the songs…", "23 of 80 songs", or its summary.
String fetchBatchStatus(FetchBatch b) => switch (b.status) {
      FetchBatchStatus.starting => 'Getting the songs…',
      FetchBatchStatus.running => '${b.added + b.owned + b.lossy + b.failed} of ${b.total} songs',
      FetchBatchStatus.done => b.summary,
      FetchBatchStatus.failed => b.error ?? 'Download didn’t finish. Tap to try again.',
    };

/// A download's state as a 24 pt glyph: spinner, progress ring, check or
/// warning. With no job yet: the action the row offers (download, or play
/// when the song is already in the library).
class FetchJobIndicator extends StatelessWidget {
  final FetchJob? job;
  final bool inLibrary;
  const FetchJobIndicator({super.key, required this.job, this.inLibrary = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final j = job;
    if (j == null) {
      return NaviIcon(
        inLibrary ? NaviGlyph.playCircle : NaviGlyph.downloadCircle,
        size: 24,
        color: t.accent,
      );
    }
    return switch (j.phase) {
      FetchJobPhase.preparing || FetchJobPhase.adding => const CupertinoActivityIndicator(),
      FetchJobPhase.downloading => _Ring(value: j.progress == 0 ? null : j.progress),
      FetchJobPhase.ready || FetchJobPhase.duplicate =>
        NaviIcon(NaviGlyph.checkCircle, size: 24, color: t.positive, filled: true),
      FetchJobPhase.rejected || FetchJobPhase.failed =>
        NaviIcon(NaviGlyph.alert, size: 24, color: t.danger),
    };
  }
}

/// [FetchJobIndicator] for an album / playlist: download glyph, overall
/// progress ring, check or warning.
class FetchBatchIndicator extends StatelessWidget {
  final FetchBatch? batch;
  const FetchBatchIndicator({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final b = batch;
    return switch (b?.status) {
      null => NaviIcon(NaviGlyph.downloadCircle, size: 24, color: t.accent),
      FetchBatchStatus.starting => const CupertinoActivityIndicator(),
      FetchBatchStatus.running => _Ring(value: b!.progress == 0 ? null : b.progress),
      FetchBatchStatus.done => NaviIcon(NaviGlyph.checkCircle, size: 24, color: t.positive, filled: true),
      FetchBatchStatus.failed => NaviIcon(NaviGlyph.alert, size: 24, color: t.danger),
    };
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
