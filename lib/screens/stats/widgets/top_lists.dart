import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/library_provider.dart';
import '../../../widgets/cover_art.dart';
import 'stat_card.dart';

/// Top artists for the period, with how their plays compare to the leader.
class TopArtistsCard extends ConsumerWidget {
  final List<Map<String, dynamic>> artists;
  const TopArtistsCard({super.key, required this.artists});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = artists.take(5).toList();
    final max = top.fold<int>(0, (m, a) => (a['play_count'] as int? ?? 0) > m ? a['play_count'] as int : m);
    return StatCard(
      title: 'Top Artists',
      child: top.isEmpty
          ? const _Empty('No artist has enough plays in this period yet.')
          : Column(children: [
              for (final (i, a) in top.indexed)
                _RankedRow(
                  rank: i + 1,
                  title: a['artist']?.toString() ?? 'Unknown Artist',
                  plays: a['play_count'] as int? ?? 0,
                  share: max == 0 ? 0 : (a['play_count'] as int? ?? 0) / max,
                  art: ref.watch(artistCoverUrlProvider(a['artist']?.toString() ?? '')).asData?.value,
                  circular: true,
                  last: i == top.length - 1,
                ),
            ]),
    );
  }
}

/// Top songs for the period, with how much of each you actually heard.
class TopSongsCard extends ConsumerWidget {
  final List<Map<String, dynamic>> tracks;
  const TopSongsCard({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    // The server can list one song under several file ids; show it once.
    final seen = <String>{};
    final top = [
      for (final s in tracks)
        if (seen.add('${s['title']}|${s['artist']}')) s,
    ].take(5).toList();
    return StatCard(
      title: 'Top Songs',
      child: top.isEmpty
          ? const _Empty('No song has enough plays in this period yet.')
          : Column(children: [
              for (final (i, s) in top.indexed)
                Builder(builder: (context) {
                  final title = s['title']?.toString() ?? 'Unknown';
                  final artist = s['artist']?.toString() ?? '';
                  final heardRaw = s['avg_listen_ratio'];
                  final heard = heardRaw is num ? heardRaw.toDouble().clamp(0.0, 1.0) : 1.0;
                  return _RankedRow(
                    rank: i + 1,
                    title: title,
                    subtitle: artist,
                    plays: s['play_count'] as int? ?? 0,
                    share: heard,
                    shareColor: heard >= 0.8 ? t.positive : (heard >= 0.5 ? t.warning : t.danger),
                    shareLabel: '${(heard * 100).round()}% heard',
                    art: ref.watch(songCoverUrlProvider('$title|$artist')).asData?.value,
                    last: i == top.length - 1,
                  );
                }),
            ]),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int rank;
  final String title;
  final String? subtitle;
  final int plays;
  final double share;
  final Color? shareColor;
  final String? shareLabel;
  final String? art;
  final bool circular;
  final bool last;

  const _RankedRow({
    required this.rank,
    required this.title,
    this.subtitle,
    required this.plays,
    required this.share,
    this.shareColor,
    this.shareLabel,
    required this.art,
    this.circular = false,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm + 2),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.outline, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: t.callout.copyWith(
                color: rank == 1 ? t.accent : t.textSecondary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          CoverArt(
            url: art,
            size: 44,
            radius: Radii.thumb,
            circular: circular,
            placeholderIcon: circular ? CupertinoIcons.person_fill : CupertinoIcons.music_note,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                const SizedBox(height: Space.xs + 2),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            Container(height: 3, color: t.fill),
                            FractionallySizedBox(
                              widthFactor: share.clamp(0.0, 1.0),
                              child: Container(height: 3, color: shareColor ?? t.accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (shareLabel != null) ...[
                      const SizedBox(width: Space.sm),
                      Text(shareLabel!, style: t.caption2),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            '$plays',
            style: t.callout.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);

  @override
  Widget build(BuildContext context) => Text(message, style: ThemeTokens.of(context).subheadline);
}
