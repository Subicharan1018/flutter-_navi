import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../widgets/cover_art.dart';
import '../../data/trending_models.dart';
import 'chart_details.dart';

/// One chart song, as in Apple Music's Top charts: today's rank with its
/// movement underneath, the cover, title and artist. A song that isn't in
/// the library is dimmed and says why.
///
/// [detailed] (the Trending page) adds the source's numbers: a stats line,
/// Billboard's chips, LW / PEAK / WKS columns once the row is wide enough,
/// and a chevron when the row opens to show more.
class ChartRow extends ConsumerWidget {
  static const double height = 60;
  static const double rankWidth = 34;
  static const double art = 46;

  /// Row width from which Billboard's columns fit beside the title.
  static const double columnsFrom = 560;

  final ChartEntry entry;
  final VoidCallback onTap;
  final bool showSeparator;
  final bool detailed;
  final bool expanded;

  const ChartRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.showSeparator = true,
    this.detailed = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    // The library's own cover once the song is in it; the chart's until then.
    final artUrl = entry.playable ? ref.read(subsonicServiceProvider).getCoverArtUrl(entry.songId!) : entry.coverUrl;
    final why = entry.unavailableLine;
    final dim = !entry.playable;
    final wide = detailed && entry.billboard != null && MediaQuery.sizeOf(context).width >= columnsFrom;
    final stats = detailed ? chartStatsLine(entry, withBillboardColumns: wide) : null;
    final badges = detailed ? ChartBadges.labels(entry) : const <String>[];
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.body.copyWith(color: dim ? t.textMuted : t.textPrimary),
        ),
        Text(
          why == null ? entry.artist : '${entry.artist} · $why',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.footnote.copyWith(color: dim ? t.textMuted : t.textSecondary),
        ),
        if (stats != null)
          Text(
            stats,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption1.copyWith(color: t.textMuted, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          ChartBadges(entry: entry),
        ],
      ],
    );
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.99,
      semanticLabel: [
        '${entry.rank}. ${entry.title} by ${entry.artist}',
        ?movementLabel(entry),
        ?why,
        ?stats,
        ...badges,
        if (detailed && entry.hasDetails) expanded ? 'expanded' : 'double tap for details',
      ].join(', '),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height, maxHeight: detailed ? double.infinity : height),
        child: Row(
          children: [
            const SizedBox(width: Space.gutter),
            SizedBox(width: rankWidth, child: _Rank(entry: entry)),
            Opacity(opacity: dim ? 0.45 : 1, child: CoverArt(url: artUrl, size: art, radius: Radii.thumb)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: height),
                padding: EdgeInsets.only(right: Space.gutter, top: detailed ? Space.sm : 0, bottom: detailed ? Space.sm : 0),
                decoration: BoxDecoration(
                  border: showSeparator && !expanded ? Border(bottom: BorderSide(color: t.outline, width: 0.5)) : null,
                ),
                child: Row(
                  children: [
                    Expanded(child: text),
                    if (wide) BillboardColumns(details: entry.billboard!),
                    if (detailed && entry.hasDetails)
                      Padding(
                        padding: const EdgeInsets.only(left: Space.sm),
                        child: AnimatedRotation(
                          turns: expanded ? 0.25 : 0,
                          duration: Motion.fast,
                          child: Icon(CupertinoIcons.chevron_forward, size: 14, color: t.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Up 3", "New" … for screen readers; null when there's nothing to say.
String? movementLabel(ChartEntry e) => switch (e.movement) {
      ChartMovement.up => 'up ${e.change}',
      ChartMovement.down => 'down ${e.change}',
      ChartMovement.isNew => 'new entry',
      ChartMovement.reentry => 're-entry',
      ChartMovement.same || null => null,
    };

class _Rank extends StatelessWidget {
  final ChartEntry entry;
  const _Rank({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.rank}',
          style: t.callout.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 1),
        MovementMark(entry: entry),
      ],
    );
  }
}

/// The small marker under a rank: ▲ / ▼ (monochrome, like the rest of the
/// chrome), "NEW" / "RE" (re-entry), or a dash when the song held its place.
class MovementMark extends StatelessWidget {
  final ChartEntry entry;
  const MovementMark({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final small = t.caption2.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ExcludeSemantics(
      child: switch (entry.movement) {
        ChartMovement.up => Icon(CupertinoIcons.arrowtriangle_up_fill, size: 8, color: t.textPrimary),
        ChartMovement.down => Icon(CupertinoIcons.arrowtriangle_down_fill, size: 8, color: t.textMuted),
        ChartMovement.isNew => Text('NEW', style: small.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700)),
        ChartMovement.reentry => Text('RE', style: small.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700)),
        ChartMovement.same => Text('–', style: small.copyWith(color: t.textMuted)),
        null => const SizedBox(height: 8),
      },
    );
  }
}
