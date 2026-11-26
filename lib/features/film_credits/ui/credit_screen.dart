import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/format.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/artwork_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../../../widgets/ui/swipe_actions.dart';
import '../logic/credit_index.dart';
import '../logic/film_credits_providers.dart';
import 'credit_widgets.dart';

/// A music director's, lyricist's or singer's page: everything they did in the library, by film.
/// Someone credited in more than one role gets plain words under the title to filter by role.
class CreditScreen extends ConsumerStatefulWidget {
  /// [nameKey] of the person.
  final String personKey;
  final String name;
  final CreditRole? role;
  const CreditScreen({super.key, required this.personKey, required this.name, this.role});

  @override
  ConsumerState<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends ConsumerState<CreditScreen> {
  CreditRole? _role;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
  }

  void _play(List<Song> songs, {required bool shuffle}) {
    if (songs.isEmpty) return;
    final n = ref.read(playerProvider.notifier);
    shuffle
        ? n.playPlaylist(songs, shuffle: true, playlistName: widget.name)
        : n.setQueue(songs, 0, playlistName: widget.name, unshuffledSongs: songs);
  }

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(personProvider(widget.personKey));
    final index = ref.watch(creditIndexProvider);
    final loading = ref.watch(creditIndexProvider.select((i) => i.people.isEmpty));
    final svc = ref.read(subsonicServiceProvider);
    // A role this person doesn't have (a stale link) falls back to everything.
    final role = person != null && person.byRole[_role]?.isNotEmpty == true ? _role : null;
    final songs = person == null ? const <Song>[] : (role == null ? person.songs : person.byRole[role]!);
    final groups = person == null ? const <({FilmEntry? film, List<Song> songs})>[] : groupByFilm(index, songs);
    final ordered = [for (final g in groups) ...g.songs];
    final cover = ordered.isEmpty ? null : ordered.first.coverArt;
    final films = groups.where((g) => g.film != null).length;

    return ArtworkPage(
      paletteCoverId: cover,
      artistStyle: true,
      art: (size) => CoverArt(
        url: cover == null ? null : svc.getCoverArtUrl(cover),
        size: size,
        radius: 0,
        placeholderIcon: NaviGlyph.mic,
      ),
      title: person?.name ?? widget.name,
      subtitle: person == null ? null : [for (final r in person.roles) r.label].join(' · '),
      detail: person == null ? null : '${songCount(songs.length)}${films > 0 ? ' · ${films == 1 ? '1 film' : '$films films'}' : ''}',
      buttons: PlayShuffleButtons(
        onPlay: ordered.isEmpty ? null : () => _play(ordered, shuffle: false),
        onShuffle: ordered.isEmpty ? null : () => _play(ordered, shuffle: true),
      ),
      slivers: person == null
          ? [
              if (loading)
                const SliverToBoxAdapter(child: TrackListSkeleton(rows: 5))
              else
                const SliverFillRemaining(
                  child: MessageState(
                    icon: NaviGlyph.mic,
                    title: 'No songs credited here',
                    message: 'Songs that name this person appear here once the library syncs.',
                  ),
                ),
            ]
          : [
              if (person.roles.length > 1)
                SliverToBoxAdapter(
                  child: RoleTabs(
                    roles: person.roles,
                    selected: role,
                    counts: {for (final r in person.roles) r: person.byRole[r]!.length},
                    total: person.songs.length,
                    onSelect: (r) => setState(() => _role = r),
                  ),
                ),
              for (final g in groups) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: g.film == null ? 'Other Songs' : g.film!.title,
                    onTap: g.film == null ? null : () => openFilm(context, g.film!.key, g.film!.title),
                  ),
                ),
                if (g.film?.year != null) SliverToBoxAdapter(child: _YearLine(year: g.film!.year!)),
                SliverFixedExtentList(
                  itemExtent: SongTile.extent,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final song = g.songs[i];
                      return SwipeActions.queue(
                        rowKey: ValueKey('credit_${song.id}'),
                        context: context,
                        onPlayNext: () => queueSongs(context, ref, [song], next: true),
                        onPlayLast: () => queueSongs(context, ref, [song], next: false),
                        child: SongTile(
                          song: song,
                          onTap: () => ref
                              .read(playerProvider.notifier)
                              .setQueue(ordered, ordered.indexOf(song), playlistName: widget.name, unshuffledSongs: ordered),
                        ),
                      );
                    },
                    childCount: g.songs.length,
                  ),
                ),
              ],
            ],
    );
  }
}

/// The film's year, tucked under its name.
class _YearLine extends StatelessWidget {
  final int year;
  const _YearLine({required this.year});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), 4),
        child: Text('$year', style: ThemeTokens.of(context).footnote.copyWith(color: ThemeTokens.of(context).textMuted)),
      );
}
