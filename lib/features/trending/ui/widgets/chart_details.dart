import 'package:flutter/cupertino.dart';

import '../../../../core/theme.dart';
import '../../../../utils/format.dart';
import '../../../../widgets/ui/media.dart' show TintedButton;
import '../../data/trending_models.dart';
import 'chart_row.dart' show ChartRow;

/// One quiet line of the source's numbers under a row's artist:
/// "LW 6 · Peak 2 · 27 wks" (Billboard) or "6.7M plays · Telugu · 2026" (JioSaavn).
String? chartStatsLine(ChartEntry e, {bool withBillboardColumns = false}) {
  final bb = e.billboard;
  if (bb != null) {
    if (withBillboardColumns) return null;          // the columns say it
    return [
      'LW ${bb.lastWeek ?? '–'}',
      if (bb.peak != null) 'Peak ${bb.peak}',
      if (bb.weeksOnChart != null) '${bb.weeksOnChart} ${bb.weeksOnChart == 1 ? 'wk' : 'wks'}',
    ].join(' · ');
  }
  final sv = e.saavn;
  if (sv != null) {
    final parts = [
      if (sv.playCount != null) '${compactCount(sv.playCount!)} plays',
      ?sv.language,
      if (sv.year != null) '${sv.year}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
  return null;
}

/// Billboard's markers as small monochrome chips: weeks at No. 1, then the
/// row's awards ("Highest ranking debut", "Gains In Performance").
class ChartBadges extends StatelessWidget {
  final ChartEntry entry;
  const ChartBadges({super.key, required this.entry});

  static List<String> labels(ChartEntry e) {
    final bb = e.billboard;
    if (bb == null) return const [];
    return [
      if ((bb.weeksAtNo1 ?? 0) > 0) 'No. 1 · ${bb.weeksAtNo1} ${bb.weeksAtNo1 == 1 ? 'wk' : 'wks'}',
      ...bb.awards,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final shown = labels(entry);
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final (i, l) in shown.indexed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
            decoration: BoxDecoration(
              // The No. 1 marker is the one filled chip; awards stay tinted.
              color: i == 0 && l.startsWith('No. 1') ? t.accent : t.fill,
              borderRadius: BorderRadius.circular(Radii.capsule),
            ),
            child: Text(
              l,
              style: t.caption2.copyWith(
                color: i == 0 && l.startsWith('No. 1') ? t.onAccent : t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Billboard's LW · PEAK · WKS columns, for rows wide enough to hold them.
class BillboardColumns extends StatelessWidget {
  static const double width = 3 * _col;
  static const double _col = 44;

  final BillboardDetails details;
  final bool header;
  const BillboardColumns({super.key, required this.details}) : header = false;
  const BillboardColumns.header({super.key})
      : details = const BillboardDetails(),
        header = true;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    Widget cell(String text) => SizedBox(
          width: _col,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: (header ? t.caption2 : t.footnote.copyWith(color: t.textPrimary))
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        );
    if (header) return Row(mainAxisSize: MainAxisSize.min, children: [cell('LW'), cell('PEAK'), cell('WKS')]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      cell('${details.lastWeek ?? '–'}'),
      cell('${details.peak ?? '–'}'),
      cell('${details.weeksOnChart ?? '–'}'),
    ]);
  }
}

/// Everything else the source says, shown when a row is opened, with Play
/// (or why it can't play) underneath.
class ChartDetailsPanel extends StatelessWidget {
  final ChartEntry entry;
  final VoidCallback onPlay;
  const ChartDetailsPanel({super.key, required this.entry, required this.onPlay});

  static List<(String, String)> facts(ChartEntry e) {
    String pos(int? p, String? date) => [if (p != null) 'No. $p', ?date].join(' · ');
    String names(List<String> l) => l.join(', ');
    final bb = e.billboard;
    final sv = e.saavn;
    return [
      if (bb != null) ...[
        if (bb.lastWeek != null) ('Last week', 'No. ${bb.lastWeek}'),
        if (bb.debutPosition != null || bb.debutDate != null) ('Debut', pos(bb.debutPosition, bb.debutDate)),
        if (bb.peakPosition != null || bb.peakDate != null) ('Peak', pos(bb.peakPosition, bb.peakDate)),
        if (bb.weeksOnChart != null) ('Weeks on chart', '${bb.weeksOnChart}'),
        if ((bb.weeksAtNo1 ?? 0) > 0) ('Weeks at No. 1', '${bb.weeksAtNo1}'),
        if (bb.songwriters.isNotEmpty) ('Songwriters', names(bb.songwriters)),
        if (bb.producers.isNotEmpty) ('Producers', names(bb.producers)),
        if (bb.label != null) ('Label', bb.label!),
      ],
      if (sv != null) ...[
        if (sv.playCount != null) ('Plays', _grouped(sv.playCount!)),
        if (sv.releaseDate != null) ('Released', _date(sv.releaseDate!)) else if (sv.year != null) ('Year', '${sv.year}'),
        if (sv.language != null) ('Language', sv.language!),
        if (sv.album != null) ('Album', sv.album!),
        if (sv.music.isNotEmpty) ('Music', names(sv.music)),
        if (sv.lyricists.isNotEmpty) ('Lyrics', names(sv.lyricists)),
        if (sv.singers.isNotEmpty) ('Singers', names(sv.singers)),
        if (sv.durationS != null) ('Length', formatTrackDuration(sv.durationS!)),
        if (sv.explicit) ('Explicit', 'Yes'),
        if (sv.label != null) ('Label', sv.label!),
        if (sv.copyright != null) ('Copyright', sv.copyright!),
      ],
    ];
  }

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      // Lined up with the title, past the rank and the cover.
      padding: const EdgeInsets.fromLTRB(
          Space.gutter + ChartRow.rankWidth + ChartRow.art + Space.md, 0, Space.gutter, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in facts(entry))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 104, child: Text(k, style: t.footnote.copyWith(color: t.textMuted))),
                  Expanded(child: Text(v, style: t.footnote.copyWith(color: t.textPrimary))),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          if (entry.playable)
            TintedButton(icon: CupertinoIcons.play_fill, label: 'Play', height: 36, onTap: onPlay)
          else
            Text(entry.unavailableLine ?? '', style: t.footnote.copyWith(color: t.textMuted)),
        ],
      ),
    );
  }
}
