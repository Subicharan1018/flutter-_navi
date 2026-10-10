import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/artist.dart';
import '../models/search_results.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/controls.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';
import 'artist_screen.dart';
import 'genre_screen.dart';

/// Apple Music's Search: recent searches and Browse by genre while idle;
/// Artists, Albums and Songs once you type.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _debounce = Duration(milliseconds: 300);

  late final _controller = TextEditingController(text: ref.read(searchQueryProvider));
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => ref.read(searchQueryProvider.notifier).state = text.trim());
  }

  void _searchFor(String text) {
    _timer?.cancel();
    _controller.text = text;
    ref.read(searchQueryProvider.notifier).state = text;
  }

  /// A result was used: remember the query that found it.
  void _remember() => ref.read(searchHistoryProvider.notifier).addQuery(ref.read(searchQueryProvider));

  @override
  Widget build(BuildContext context) {
    // The desktop sidebar can start a search too; mirror it into the field.
    ref.listen(searchQueryProvider, (_, next) {
      if (_controller.text.trim() != next) _controller.text = next;
    });
    final query = ref.watch(searchQueryProvider);

    return LargeTitlePage(
      title: 'Search',
      header: NaviSearchField(
        controller: _controller,
        placeholder: 'Artists, Albums, Songs',
        onChanged: _onChanged,
        onSubmitted: (q) {
          _searchFor(q.trim());
          _remember();
        },
      ),
      onRefresh: query.isEmpty ? () async => ref.invalidate(genresProvider) : null,
      slivers: query.isEmpty
          ? [_RecentSearches(onTap: _searchFor), const _BrowseGenres()]
          : [_Results(query: query, onUsed: _remember)],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Idle state
// ─────────────────────────────────────────────────────────────────────────────

class _RecentSearches extends ConsumerWidget {
  final ValueChanged<String> onTap;
  const _RecentSearches({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverList.list(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.sm, 0),
        child: Row(
          children: [
            Expanded(child: Text('Recently Searched', style: t.title3)),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              onPressed: () => ref.read(searchHistoryProvider.notifier).clearHistory(),
              child: Text('Clear', style: t.body.copyWith(color: t.accent)),
            ),
          ],
        ),
      ),
      for (final (i, q) in history.indexed)
        Dismissible(
          key: ValueKey('recent_$q'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: t.danger,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Space.xl),
            child: Text('Delete', style: t.headline.copyWith(color: Colors.white)),
          ),
          onDismissed: (_) => ref.read(searchHistoryProvider.notifier).removeQuery(q),
          child: CollectionRow(
            title: q,
            leading: Icon(CupertinoIcons.search, size: 18, color: t.textMuted),
            showChevron: false,
            showSeparator: i < history.length - 1,
            onTap: () => onTap(q),
          ),
        ),
    ]);
  }
}

class _BrowseGenres extends ConsumerWidget {
  const _BrowseGenres();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider).asData?.value ?? const <Genre>[];
    if (genres.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: SectionHeader(title: 'Browse by Genre')),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        sliver: SliverLayoutBuilder(
          builder: (context, c) => SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: c.crossAxisExtent >= 900 ? 4 : c.crossAxisExtent >= 600 ? 3 : 2,
              crossAxisSpacing: Space.md,
              mainAxisSpacing: Space.md,
              mainAxisExtent: 84,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _GenreTile(genre: genres[i]),
              childCount: genres.length,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _GenreTile extends StatelessWidget {
  final Genre genre;
  const _GenreTile({required this.genre});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: () => navigateInApp(context, GenreScreen(genre: genre.name)),
      scaleFactor: 0.97,
      semanticLabel: genre.name,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(color: t.bgSurface, borderRadius: BorderRadius.circular(Radii.group)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(genre.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headline),
            Text(
              genre.albumCount == 1 ? '1 album' : '${genre.albumCount} albums',
              style: t.footnote,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results
// ─────────────────────────────────────────────────────────────────────────────

class _Results extends ConsumerStatefulWidget {
  final String query;
  final VoidCallback onUsed;
  const _Results({required this.query, required this.onUsed});

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  /// Last results shown, kept on screen while the next query loads so the
  /// list doesn't flash to a skeleton on every keystroke.
  SearchResults? _last;

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final onUsed = widget.onUsed;
    final results = ref.watch(searchProvider(query));
    if (results.asData?.value case final value?) _last = value;
    final data = results.isLoading ? _last : (results.asData?.value ?? SearchResults.empty);

    if (results.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: MessageState.error(
          title: 'Search isn’t available',
          onRetry: () => ref.invalidate(searchProvider(query)),
        ),
      );
    }
    if (data == null) {
      return const SliverToBoxAdapter(child: TrackListSkeleton());
    }
    if (data.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: MessageState(
          icon: CupertinoIcons.search,
          title: 'No results for “$query”',
          message: 'Check the spelling, or try an artist, album or song name.',
        ),
      );
    }

    final svc = ref.read(subsonicServiceProvider);
    final songs = data.songs;
    return SliverMainAxisGroup(slivers: [
      if (data.artists.isNotEmpty)
        SliverToBoxAdapter(
          child: MediaShelf(
            title: 'Artists',
            cardSize: 110,
            hasSubtitle: false,
            itemCount: data.artists.length,
            itemBuilder: (context, i) {
              final a = data.artists[i];
              return MediaCard(
                title: a.name,
                artUrl: svc.getCoverArtUrl(a.coverArtId),
                size: 110,
                circular: true,
                placeholderIcon: CupertinoIcons.person_fill,
                onTap: () {
                  onUsed();
                  navigateInApp(context, ArtistScreen(artistId: a.id, name: a.name));
                },
              );
            },
          ),
        ),
      if (data.albums.isNotEmpty)
        SliverToBoxAdapter(
          child: MediaShelf(
            title: 'Albums',
            itemCount: data.albums.length,
            itemBuilder: (context, i) {
              final a = data.albums[i];
              final art = svc.getCoverArtUrl(a.coverArt);
              return MediaCard(
                title: a.name,
                subtitle: a.artist,
                artUrl: art,
                size: 150,
                placeholderIcon: CupertinoIcons.music_albums,
                onTap: () {
                  onUsed();
                  navigateInApp(context, AlbumDetailsScreen(album: a));
                },
                onLongPress: () => showCollectionActions(
                  context,
                  title: a.name,
                  subtitle: a.artist,
                  artUrl: art,
                  placeholderIcon: CupertinoIcons.music_albums,
                  loadSongs: () => svc.getAlbum(a.id),
                ),
              );
            },
          ),
        ),
      if (songs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Songs')),
        SliverFixedExtentList(
          itemExtent: SongTile.extent,
          delegate: SliverChildBuilderDelegate(
            (context, i) => SongTile(
              song: songs[i],
              onTap: () {
                onUsed();
                ref.read(playerProvider.notifier).setQueue(songs, i, playlistName: 'Search');
              },
            ),
            childCount: songs.length,
          ),
        ),
      ],
    ]);
  }
}
