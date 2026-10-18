import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../features/online_fetch/data/fetch_models.dart' show looksLikeLink;
import '../features/online_fetch/logic/online_fetch_providers.dart';
import '../features/online_fetch/ui/search_online_row.dart';
import '../features/online_fetch/ui/send_playlist_sheet.dart';
import '../models/catalog.dart';
import '../models/search_results.dart';
import '../player/artwork.dart' show coverPaletteProvider;
import '../providers/catalog_provider.dart';
import '../providers/pins_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/collection_actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui/controls.dart';
import '../widgets/ui/large_title_page.dart';
import '../widgets/ui/media.dart';
import '../widgets/ui/states.dart';
import 'album_details_screen.dart';
import 'artist_screen.dart';
import 'category_screen.dart';

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
      onRefresh: query.isEmpty ? () => ref.read(catalogProvider.notifier).refresh() : null,
      slivers: query.isEmpty
          ? [_RecentSearches(onTap: _searchFor), const _BrowseCategories()]
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

/// Browse the library by what the songs are: their language (Tamil, English,
/// songs in more than one, then every other language) and their genre. Built
/// from the shuffle server's catalog, which detects language from lyrics,
/// vocals and sources and cleans up genre tags.
class _BrowseCategories extends ConsumerWidget {
  const _BrowseCategories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(catalogProvider).asData?.value;
    if (doc == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final languages = [
      ...doc.languages.take(2),
      ?doc.multilingual,
      ...doc.languages.skip(2),
    ];
    return SliverMainAxisGroup(slivers: [
      if (languages.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Languages')),
        _CategoryGrid(categories: languages),
      ],
      if (doc.genres.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Genres')),
        _CategoryGrid(categories: doc.genres),
      ],
    ]);
  }
}

class _CategoryGrid extends StatelessWidget {
  final List<CatalogCategory> categories;
  const _CategoryGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      sliver: SliverLayoutBuilder(
        builder: (context, c) => SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: c.crossAxisExtent >= 900 ? 4 : c.crossAxisExtent >= 600 ? 3 : 2,
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
            mainAxisExtent: 108,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _CategoryTile(category: categories[i]),
            childCount: categories.length,
          ),
        ),
      ),
    );
  }
}

/// Apple Music's Browse tile: a block of colour sampled from one of the
/// category's covers, the name in bold white, and that cover tipped into the
/// bottom-right corner.
class _CategoryTile extends ConsumerWidget {
  final CatalogCategory category;
  const _CategoryTile({required this.category});

  /// Luminance at which white bold text still clears 4.5:1.
  static const double _maxLuminance = 0.18;

  /// The cover's hue as Apple's Browse colours are: saturated, never muddy,
  /// and dark enough for white text. Steps lightness down until it reads.
  static Color _tileColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    // A black-and-white cover stays neutral rather than gaining a hue.
    final saturation = hsl.saturation < 0.15 ? hsl.saturation : hsl.saturation.clamp(0.5, 0.78);
    var c = hsl.withSaturation(saturation).withLightness(0.4);
    while (c.toColor().computeLuminance() > _maxLuminance && c.lightness > 0.2) {
      c = c.withLightness(c.lightness - 0.02);
    }
    return c.toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final cover = ref.watch(categoryCoverProvider(category));
    final palette = cover == null ? null : ref.watch(coverPaletteProvider(cover)).asData?.value;
    final fill = palette == null ? t.bgSurface : _tileColor(palette.base);
    final url = cover == null ? null : ref.read(subsonicServiceProvider).getCoverArtUrl(cover);
    final count = category.count == 1 ? '1 song' : '${category.count} songs';

    return CupertinoClickable(
      onTap: () => navigateInApp(context, CategoryScreen(category: category)),
      scaleFactor: 0.97,
      semanticLabel: '${category.name}, $count',
      child: LayoutBuilder(builder: (context, c) {
        final art = c.maxHeight * 0.78;
        return AnimatedContainer(
          duration: Motion.slow,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.cover)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (url != null)
                Positioned(
                  right: -art * 0.18,
                  bottom: -art * 0.12,
                  child: Transform.rotate(
                    angle: 0.42,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(-2, 4))],
                      ),
                      child: CoverArt(url: url, size: art, radius: Radii.thumb),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xxxl + Space.lg, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.headline.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(count, style: t.caption1.copyWith(color: Colors.white.withValues(alpha: 0.78))),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
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
      final online = ref.watch(onlineFetchEnabledProvider).asData?.value ?? false;
      if (online && looksLikeLink(query)) {
        // A pasted playlist link: offer to send it rather than "no results".
        return SliverFillRemaining(
          hasScrollBody: false,
          child: MessageState(
            icon: CupertinoIcons.link,
            title: 'Playlist link',
            message: 'Add its songs in lossless quality and make it a playlist in your library.',
            actionLabel: 'Send Playlist',
            onAction: () => showSendPlaylist(context, link: query),
          ),
        );
      }
      return SliverFillRemaining(hasScrollBody: false, child: NoLibraryResults(query: query));
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
                  pin: Pin.album(a),
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
      SliverToBoxAdapter(child: SearchOnlineRow(query: query)),
    ]);
  }
}
