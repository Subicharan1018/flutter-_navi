import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/composer.dart' show nameKey;
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../logic/credit_index.dart';
import '../logic/film_credits_providers.dart';
import 'credit_widgets.dart';

/// Every film in the library, A–Z.
class FilmsPage extends ConsumerWidget {
  const FilmsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final films = ref.watch(creditIndexProvider.select((i) => i.filmList));
    return LargeTitlePage(
      title: 'Films',
      slivers: films.isEmpty
          ? const [
              SliverFillRemaining(
                child: MessageState(
                  icon: NaviGlyph.note,
                  title: 'No films yet',
                  message: 'Songs tagged with the film they are from appear here.',
                ),
              ),
            ]
          : [
              SliverFixedExtentList(
                itemExtent: 62,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => FilmRow(film: films[i], showSeparator: i < films.length - 1),
                  childCount: films.length,
                ),
              ),
            ],
    );
  }
}

/// Every person credited in one role, most songs first.
class PeoplePage extends ConsumerWidget {
  final CreditRole role;
  const PeoplePage({super.key, required this.role});

  static String titleOf(CreditRole r) => switch (r) {
        CreditRole.musicDirector => 'Music Directors',
        CreditRole.lyricist => 'Lyricists',
        CreditRole.singer => 'Singers',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(creditIndexProvider.select((i) => i.peopleIn(role)));
    return LargeTitlePage(
      title: titleOf(role),
      slivers: people.isEmpty
          ? [
              SliverFillRemaining(
                child: MessageState(
                  icon: NaviGlyph.mic,
                  title: 'No ${titleOf(role).toLowerCase()} yet',
                  message: 'They appear here once songs name them.',
                ),
              ),
            ]
          : [
              SliverFixedExtentList(
                itemExtent: 62,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => PersonRow(person: people[i], role: role, showSeparator: i < people.length - 1),
                  childCount: people.length,
                ),
              ),
            ],
    );
  }
}

/// Search's idle Browse: Films and the three credit lists as plain rows. Renders nothing until
/// the library has films, so a library with no film tags shows no dead end.
class CreditsBrowseSection extends ConsumerWidget {
  const CreditsBrowseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(creditIndexProvider.select((i) => (
          i.films.length,
          i.peopleIn(CreditRole.musicDirector).length,
          i.peopleIn(CreditRole.lyricist).length,
          i.peopleIn(CreditRole.singer).length,
        )));
    final rows = <(String, int, VoidCallback)>[
      if (counts.$1 > 0) ('Films', counts.$1, () => navigateInApp(context, const FilmsPage())),
      if (counts.$2 > 0)
        ('Music Directors', counts.$2, () => navigateInApp(context, const PeoplePage(role: CreditRole.musicDirector))),
      if (counts.$3 > 0)
        ('Lyricists', counts.$3, () => navigateInApp(context, const PeoplePage(role: CreditRole.lyricist))),
      if (counts.$4 > 0) ('Singers', counts.$4, () => navigateInApp(context, const PeoplePage(role: CreditRole.singer))),
    ];
    if (rows.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: SectionHeader(title: 'Films & Credits')),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => CollectionRow.destination(
          context: context,
          icon: rows[i].$1 == 'Films' ? NaviGlyph.note : NaviGlyph.mic,
          title: '${rows[i].$1}  ·  ${rows[i].$2}',
          showSeparator: i < rows.length - 1,
          onTap: rows[i].$3,
        ),
      ),
    ]);
  }
}

/// Films among the search results: the ones whose title contains the query.
final filmSearchProvider = Provider.autoDispose.family<List<FilmEntry>, String>((ref, query) {
  final q = nameKey(query);
  if (q.length < 2) return const [];
  final all = ref.watch(creditIndexProvider.select((i) => i.filmList));
  final starts = [for (final f in all) if (f.key.startsWith(q)) f];
  final has = [for (final f in all) if (!f.key.startsWith(q) && f.key.contains(q)) f];
  return [...starts, ...has].take(4).toList();
});

/// The Films section of a search: nothing when no film matches.
class FilmSearchSection extends ConsumerWidget {
  final String query;
  final VoidCallback? onBeforeOpen;
  const FilmSearchSection({super.key, required this.query, this.onBeforeOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final films = ref.watch(filmSearchProvider(query));
    if (films.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: SectionHeader(title: 'Films')),
      SliverList.builder(
        itemCount: films.length,
        itemBuilder: (context, i) => FilmRow(film: films[i], showSeparator: i < films.length - 1, onBeforeOpen: onBeforeOpen),
      ),
    ]);
  }
}

/// "In films": the films an artist is credited on, for the artist page. Nothing when none.
class ArtistFilmsSection extends ConsumerWidget {
  final String artistName;
  const ArtistFilmsSection({super.key, required this.artistName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = nameKey(artistName);
    final person = ref.watch(personProvider(key));
    final index = ref.watch(creditIndexProvider);
    if (person == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final groups = [for (final g in groupByFilm(index, person.songs)) if (g.film != null) g.film!];
    if (groups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: SectionHeader(title: 'In Films', onTap: () => openPerson(context, person.name)),
      ),
      SliverList.builder(
        itemCount: groups.length.clamp(0, 5),
        itemBuilder: (context, i) => FilmRow(
          film: groups[i],
          showSeparator: i < groups.length.clamp(0, 5) - 1,
          subtitle: [if (groups[i].year != null) '${groups[i].year}', groups[i].songs.length == 1 ? '1 song' : '${groups[i].songs.length} songs'].join(' · '),
        ),
      ),
    ]);
  }
}
