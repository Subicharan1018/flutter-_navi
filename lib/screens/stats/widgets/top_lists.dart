import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/library_provider.dart';
import '../../../widgets/cover_art.dart';
import 'stat_card.dart';

/// Top artists for the period as Apple Music shows artists: round
/// portraits on a shelf, the leader first and largest.
class TopArtistsCard extends ConsumerWidget {
  static const double _lead = 128;
  static const double _rest = 96;

  final List<Map<String, dynamic>> artists;
  const TopArtistsCard({super.key, required this.artists});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final top = artists.take(6).toList();
    return StatSection(
      title: 'Top Artists',
      child: top.isEmpty
          ? const _Empty('No artist has enough plays in this period yet.')
          : SizedBox(
              height: _lead + 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // Bleed to the screen edge like every shelf in the app.
                clipBehavior: Clip.none,
                itemCount: top.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.lg),
                itemBuilder: (context, i) {
                  final name = top[i]['artist']?.toString() ?? 'Unknown Artist';
                  final plays = top[i]['play_count'] as int? ?? 0;
                  final size = i == 0 ? _lead : _rest;
                  return SizedBox(
                    width: size,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CoverArt(
                          url: ref.watch(artistCoverUrlProvider(name)).asData?.value,
                          size: size,
                          circular: true,
                          placeholderIcon: CupertinoIcons.person_fill,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: (i == 0 ? t.headline : t.subheadline.copyWith(color: t.textPrimary)),
                        ),
                        Text(plays == 1 ? '1 play' : '$plays plays', style: t.footnote),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Top songs for the period as a ranked list, each with how much of it you
/// actually heard on average.
class TopSongsCard extends ConsumerWidget {
  final List<Map<String, dynamic>> tracks;
  const TopSongsCard({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The server can list one song under several file ids; show it once.
    final seen = <String>{};
    final top = [
      for (final s in tracks)
        if (seen.add('${s['title']}|${s['artist']}')) s,
    ].take(5).toList();
    return StatSection(
      title: 'Top Songs',
      child: top.isEmpty
          ? const _Empty('No song has enough plays in this period yet.')
          : Column(children: [
              for (final (i, s) in top.indexed)
                Builder(builder: (context) {
                  final title = s['title']?.toString() ?? 'Unknown';
                  final artist = s['artist']?.toString() ?? '';
                  final heardRaw = s['avg_listen_ratio'];
                  return _RankedRow(
                    rank: i + 1,
                    title: title,
                    subtitle: artist,
                    plays: s['play_count'] as int? ?? 0,
                    heard: heardRaw is num ? heardRaw.toDouble().clamp(0.0, 1.0) : null,
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
  final String subtitle;
  final int plays;
  final double? heard;
  final String? art;
  final bool last;

  const _RankedRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.plays,
    required this.heard,
    required this.art,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // Only a song you mostly skip is worth flagging.
    final heardColor = heard != null && heard! < 0.4 ? t.danger : t.textSecondary;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: figureStyle(t, 17).copyWith(color: rank == 1 ? t.accent : t.textSecondary),
            ),
          ),
          CoverArt(url: art, size: 48, radius: Radii.thumb, placeholderIcon: CupertinoIcons.music_note),
          const SizedBox(width: Space.md),
          Expanded(
            child: DecoratedBox(
              // Apple's inset separator: starts at the text, not the edge.
              decoration: BoxDecoration(
                border: last ? null : Border(bottom: BorderSide(color: t.outline, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$plays', style: figureStyle(t, 17)),
                      if (heard != null)
                        Text('${(heard! * 100).round()}% heard', style: t.caption1.copyWith(color: heardColor)),
                    ],
                  ),
                ],
              ),
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
