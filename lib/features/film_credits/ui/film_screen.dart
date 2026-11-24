import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/artwork_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../../widgets/ui/swipe_actions.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../../online_fetch/ui/online_search_sheet.dart';
import '../data/film_info.dart';
import '../logic/credit_index.dart';
import '../logic/film_credits_providers.dart';
import 'credit_widgets.dart';

/// A film's page, in the manner of Apple Music Classical's work page: who made it as plain
/// credit lines (every name opens that person), then the songs you own, then the soundtrack's
/// other songs you do not have, with a way to look for them.
class FilmScreen extends ConsumerWidget {
  /// [nameKey] of the film's title.
  final String filmKey;
  final String title;
  const FilmScreen({super.key, required this.filmKey, required this.title});

  void _play(WidgetRef ref, FilmEntry film, {required bool shuffle}) {
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(film.songs, shuffle: true, playlistName: film.title)
        : n.setQueue(film.songs, 0, playlistName: film.title, unshuffledSongs: film.songs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final film = ref.watch(filmProvider(filmKey));
    final svc = ref.read(subsonicServiceProvider);
    final songs = film?.songs ?? const <Song>[];
    final cover = songs.isEmpty ? null : songs.first.coverArt;
    final info = film?.info;
    final md = film?.musicDirectors ?? const <String>[];
    final detail = film == null
        ? null
        : [
            if (film.year != null) '${film.year}',
            songs.length == 1 ? '1 song' : '${songs.length} songs',
            if (film.missing.isNotEmpty) '${film.missing.length} not in your library',
          ].join(' · ');

    return ArtworkPage(
      paletteCoverId: cover,
      art: (size) => CoverArt(
        url: cover == null ? null : svc.getCoverArtUrl(cover),
        size: size,
        radius: Radii.cover,
        placeholderIcon: NaviGlyph.note,
      ),
      title: film?.title ?? title,
      subtitle: md.isEmpty ? 'Film' : md.join(', '),
      onSubtitleTap: md.isEmpty ? null : () => openPerson(context, md.first, role: CreditRole.musicDirector),
      detail: detail,
      buttons: PlayShuffleButtons(
        onPlay: songs.isEmpty ? null : () => _play(ref, film!, shuffle: false),
        onShuffle: songs.isEmpty ? null : () => _play(ref, film!, shuffle: true),
      ),
      slivers: film == null
          ? const [
              SliverFillRemaining(
                child: MessageState(
                  icon: NaviGlyph.note,
                  title: 'No songs from this film',
                  message: 'Songs tagged with this film appear here once the library syncs.',
                ),
              ),
            ]
          : [
              SliverToBoxAdapter(child: _Credits(film: film, info: info)),
              const SliverToBoxAdapter(child: SectionHeader(title: 'In Your Library')),
              SliverFixedExtentList(
                itemExtent: SongTile.extent,
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final song = songs[i];
                    return SwipeActions.queue(
                      rowKey: ValueKey('film_${song.id}'),
                      context: context,
                      onPlayNext: () => queueSongs(context, ref, [song], next: true),
                      onPlayLast: () => queueSongs(context, ref, [song], next: false),
                      child: SongTile(
                        song: song,
                        onTap: () => ref
                            .read(playerProvider.notifier)
                            .setQueue(songs, i, playlistName: film.title, unshuffledSongs: songs),
                      ),
                    );
                  },
                  childCount: songs.length,
                ),
              ),
              if (film.missing.isNotEmpty) SliverToBoxAdapter(child: _MissingTracks(film: film)),
            ],
    );
  }
}

/// Director, music director, lyrics: only the lines the library or the server actually knows.
class _Credits extends StatelessWidget {
  final FilmEntry film;
  final FilmInfo? info;
  const _Credits({required this.film, required this.info});

  @override
  Widget build(BuildContext context) {
    final lines = <(String, List<String>)>[
      ('Music', film.musicDirectors),
      ('Directed by', info?.directors ?? const []),
      ('Lyrics', info?.lyricists ?? const []),
    ].where((l) => l.$2.isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(children: [
        for (final (i, l) in lines.indexed)
          RiseIn(index: i, child: CreditLine(label: l.$1, names: l.$2, showSeparator: i < lines.length - 1)),
      ]),
    );
  }
}

/// The soundtrack's other songs: quiet rows (nothing to play), each opening a search for it.
class _MissingTracks extends ConsumerWidget {
  final FilmEntry film;
  const _MissingTracks({required this.film});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final online = ref.watch(onlineFetchAvailableProvider);
    final gutter = pageGutter(context);
    final md = film.musicDirectors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Not in Your Library'),
        for (final tr in film.missing)
          CupertinoClickable(
            onTap: online ? () => showOnlineSearch(context, '${tr.title} ${film.title}') : null,
            semanticLabel: online ? 'Search online for ${tr.title}' : tr.title,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: Space.sm),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(color: t.textMuted)),
                    if (tr.artist.isNotEmpty)
                      Text(tr.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textMuted)),
                  ]),
                ),
                if (online) NaviIcon(NaviGlyph.plus, size: 18, color: t.textMuted),
              ]),
            ),
          ),
        if (online)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, Space.lg, gutter, Space.lg),
            // The hook into the existing online fetch; the "complete this soundtrack" loop is a later item.
            child: CupertinoClickable(
              onTap: () => showOnlineSearch(context, md.isEmpty ? film.title : '${film.title} ${md.first}'),
              semanticLabel: 'Find the rest of ${film.title}',
              child: Text('Find the rest of this soundtrack', style: t.body.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}
