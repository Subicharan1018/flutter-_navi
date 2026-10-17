import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/cover_art.dart';
import '../../data/fetch_models.dart';
import '../../logic/online_fetch_providers.dart';

/// One online result: title, artist · album, what kind of recording it is,
/// and — once picked — where its download is. Watches only its own job.
class FetchCandidateRow extends ConsumerWidget {
  final FetchCandidate candidate;
  final bool showSeparator;

  /// Tapped a result that isn't in the library yet (or whose download failed).
  final VoidCallback onDownload;

  /// Tapped a result that's already in the library.
  final VoidCallback onPlayOwned;

  const FetchCandidateRow({
    super.key,
    required this.candidate,
    required this.onDownload,
    required this.onPlayOwned,
    this.showSeparator = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final job = ref.watch(fetchJobsProvider.select((jobs) => jobs[candidate.id]));
    final c = candidate;
    final status = _statusLine(job, c);
    final tappable = c.inLibrary || job == null || job.phase == FetchJobPhase.failed;

    return Semantics(
      button: tappable,
      label: '${c.title}, ${c.artist}${status == null ? '' : ', $status'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: !tappable ? null : (c.inLibrary ? onPlayOwned : onDownload),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CoverArt(url: null, size: 44, radius: Radii.thumb, placeholderIcon: CupertinoIcons.music_note),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                        const SizedBox(height: 2),
                        Text(
                          [c.artist, c.album].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.subheadline,
                        ),
                        if (status != null || c.kind.label != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            status ?? c.kind.label!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote.copyWith(color: _statusColor(t, job, c)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  SizedBox(width: 28, height: 28, child: Center(child: FetchJobIndicator(job: job, inLibrary: c.inLibrary))),
                ],
              ),
              const SizedBox(height: Space.sm),
              if (showSeparator)
                Padding(
                  padding: const EdgeInsets.only(left: 44 + Space.md),
                  child: Container(height: 0.5, color: t.outline),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _statusLine(FetchJob? job, FetchCandidate c) {
    if (job == null) return c.inLibrary ? 'In your library' : null;
    return fetchJobStatus(job);
  }

  static Color _statusColor(AppThemeTokens t, FetchJob? job, FetchCandidate c) => switch (job?.phase) {
        FetchJobPhase.ready => t.positive,
        FetchJobPhase.rejected || FetchJobPhase.failed => t.danger,
        // "Cover", "Remix"…: information, so secondary text, not a warning hue.
        null when c.kind != FetchKind.original && !c.inLibrary => t.textSecondary,
        _ => t.textMuted,
      };
}

/// Where a download is, in the user's words — shared by the result rows and
/// the sheet's active-downloads banner.
String fetchJobStatus(FetchJob job) => switch (job.phase) {
      FetchJobPhase.preparing => 'Preparing…',
      FetchJobPhase.downloading => 'Downloading ${(job.progress * 100).round()}%',
      FetchJobPhase.adding => 'Adding to your library…',
      FetchJobPhase.ready => 'Added to your library',
      FetchJobPhase.duplicate => 'Already in your library',
      FetchJobPhase.rejected => 'Not available in lossless quality',
      FetchJobPhase.failed => job.error ?? 'Download didn’t finish. Tap to try again.',
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
      return Icon(
        inLibrary ? CupertinoIcons.play_circle : CupertinoIcons.arrow_down_circle,
        size: 24,
        color: t.accent,
      );
    }
    return switch (j.phase) {
      FetchJobPhase.preparing || FetchJobPhase.adding => const CupertinoActivityIndicator(),
      FetchJobPhase.downloading => CircularProgressIndicator(
          value: j.progress == 0 ? null : j.progress,
          strokeWidth: 2.5,
          color: t.accent,
          backgroundColor: t.fill,
        ),
      FetchJobPhase.ready || FetchJobPhase.duplicate =>
        Icon(CupertinoIcons.checkmark_circle_fill, size: 24, color: t.positive),
      FetchJobPhase.rejected || FetchJobPhase.failed =>
        Icon(CupertinoIcons.exclamationmark_circle, size: 24, color: t.danger),
    };
  }
}
