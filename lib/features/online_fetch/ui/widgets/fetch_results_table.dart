import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/focus/navi_focus.dart';
import '../../../../core/theme.dart';
import '../../../../widgets/art/generated_cover.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/cover_art.dart';
import '../../../../widgets/desktop_dialogs.dart';
import '../../../../widgets/ui/action_sheet.dart';
import '../../data/fetch_models.dart';
import '../../logic/online_fetch_providers.dart';
import 'fetch_candidate_row.dart';

/// Online results on Windows: a table, not a list of phone rows. 48 px rows with
/// a 36 px cover, the title and who it is by, where the download is, and the one
/// thing a click does. Hover tints a row, Enter does the row's action, and a
/// right-click opens the same choices as a menu.
class FetchResultsTable extends StatelessWidget {
  final List<FetchCandidate> candidates;

  /// Non-null while picking several songs: the picked candidate ids.
  final Set<int>? picked;

  /// Download, toggle (when picking) or open (an artist's songs).
  final ValueChanged<FetchCandidate> onPrimary;
  final ValueChanged<FetchCandidate> onPlayOwned;

  const FetchResultsTable({
    super.key,
    required this.candidates,
    required this.picked,
    required this.onPrimary,
    required this.onPlayOwned,
  });

  static const double rowHeight = 48;
  static const double art = 36;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final selecting = picked != null;
    final head = t.caption1.copyWith(color: t.textMuted, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
          child: Row(
            children: [
              if (selecting) const SizedBox(width: 24 + Space.md),
              const SizedBox(width: art + Space.md),
              Expanded(flex: 5, child: Text('Title', style: head)),
              Expanded(flex: 3, child: Text('Status', style: head)),
              const SizedBox(width: 40),
            ],
          ),
        ),
        for (final c in candidates)
          _Row(
            key: ValueKey('fetch-row-${c.id}'),
            candidate: c,
            selected: selecting && c.isSong ? picked!.contains(c.id) : null,
            onPrimary: onPrimary,
            onPlayOwned: onPlayOwned,
          ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  final FetchCandidate candidate;
  final bool? selected;
  final ValueChanged<FetchCandidate> onPrimary;
  final ValueChanged<FetchCandidate> onPlayOwned;
  const _Row({super.key, required this.candidate, required this.selected, required this.onPrimary, required this.onPlayOwned});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final c = candidate;
    final song = c.isSong;
    final job = song ? ref.watch(fetchJobsProvider.select((d) => d.jobFor(c.id))) : null;
    final batch = song ? null : ref.watch(fetchJobsProvider.select((d) => d.batchFor(c.id)));
    final selecting = selected != null;
    final status = song ? FetchCandidateRow.statusOf(job, c) : (batch == null ? null : fetchBatchStatus(batch));
    final tappable = fetchCandidateTappable(c, job: job, batch: batch, selecting: selecting);
    final owned = song && c.inLibrary && !selecting;
    final subtitle = FetchCandidateRow.subtitleOf(c);

    void activate() => owned ? onPlayOwned(c) : onPrimary(c);

    final (verb, glyph) = switch (c.type) {
      _ when owned => ('Play', NaviGlyph.play),
      _ when c.type.opensSongs => ('Open songs', NaviGlyph.chevron),
      _ when selecting => (selected! ? 'Unpick' : 'Pick', NaviGlyph.checkCircle),
      _ => ('Download', NaviGlyph.download),
    };

    return NaviFocusable(
      radius: 6,
      onTap: tappable ? activate : null,
      onSecondaryTap: () => _menu(context, tappable: tappable, verb: verb, glyph: glyph, activate: activate),
      semanticLabel: [c.title, subtitle, ?status].where((s) => s.isNotEmpty).join(', '),
      child: Container(
        height: FetchResultsTable.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: Row(
          children: [
            if (selecting) ...[
              if (selected != null)
                NaviIcon(
                  selected! ? NaviGlyph.checkCircle : NaviGlyph.ring,
                  filled: selected!,
                  size: 24,
                  color: !tappable ? t.textMuted : (selected! ? t.accent : t.textSecondary),
                )
              else
                const SizedBox(width: 24),
              const SizedBox(width: Space.md),
            ],
            if (c.type == FetchSearchType.label && (c.coverUrl == null || c.coverUrl!.isEmpty))
              SizedBox(
                key: const ValueKey('label-generated-cover'),
                width: FetchResultsTable.art,
                height: FetchResultsTable.art,
                child: GeneratedCover(name: c.title, borderRadius: Radii.thumb),
              )
            else
              CoverArt(
                url: c.coverUrl,
                size: FetchResultsTable.art,
                radius: Radii.thumb,
                circular: c.type == FetchSearchType.artist,
                placeholderIcon: switch (c.type) {
                  FetchSearchType.artist => NaviGlyph.person,
                  FetchSearchType.playlist => NaviGlyph.playlist,
                  FetchSearchType.album || FetchSearchType.label => NaviGlyph.library,
                  FetchSearchType.song => NaviGlyph.note,
                },
              ),
            const SizedBox(width: Space.md),
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w500)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption1),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                status ?? (song ? (c.kind.label ?? '') : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.footnote.copyWith(color: FetchCandidateRow.statusColorOf(t, job, batch, c)),
              ),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: switch (c.type) {
                  _ when selecting => const SizedBox.shrink(),
                  FetchSearchType.song => FetchJobIndicator(job: job, inLibrary: c.inLibrary, blocked: c.blocked),
                  FetchSearchType.artist || FetchSearchType.label => NaviIcon(NaviGlyph.chevron, size: 16, color: t.textMuted),
                  _ => FetchBatchIndicator(batch: batch),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context, {required bool tappable, required String verb, required NaviGlyph glyph, required VoidCallback activate}) {
    final c = candidate;
    showDesktopMenu<void>(
      context: context,
      builder: (_) => SheetGroup(children: [
        SheetAction(label: verb, hint: 'Enter', icon: glyph, onTap: tappable ? activate : null),
        SheetAction(
          label: 'Copy Title',
          icon: NaviGlyph.link,
          onTap: () => Clipboard.setData(ClipboardData(text: [c.title, if (c.artist.isNotEmpty) c.artist].join(' — '))),
        ),
      ]),
    );
  }
}
