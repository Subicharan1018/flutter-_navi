import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/search_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/song_tile.dart';
import '../core/theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = query;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeTokens.of(context).isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              backgroundColor: ThemeTokens.of(context).bgBase,
              elevation: 0,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                centerTitle: false,
                title: Text(
                  'Search',
                  style: TextStyle(
                    color: ThemeTokens.of(context).textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchHeaderDelegate(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      // PERF-4: reduced from σ16 to σ10 — saves one GPU pass, still frosted.
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: ThemeTokens.of(context).bgSurface.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ThemeTokens.of(context).outline),
                        ),
                        child: TextField(
                          controller: _controller,
                          onChanged: _onSearchChanged,
                          style: TextStyle(color: ThemeTokens.of(context).textPrimary, fontSize: 17),
                          cursorColor: ThemeTokens.of(context).accent,
                          decoration: InputDecoration(
                            hintText: 'Artists, Songs, Lyrics and More',
                            hintStyle: TextStyle(color: ThemeTokens.of(context).textMuted.withOpacity(0.6), fontSize: 15),
                            prefixIcon: Icon(Icons.search_rounded, color: ThemeTokens.of(context).textMuted, size: 24),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_query.isEmpty) ...[
              _SearchHistorySliver(
                onTap: (q) {
                  _controller.text = q;
                  _onSearchChanged(q);
                },
              ),
            ] else ...[
              _SearchResultsSliver(query: _query),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _SearchHistorySliver extends ConsumerWidget {
  final Function(String) onTap;
  const _SearchHistorySliver({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);

    if (history.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_rounded, color: ThemeTokens.of(context).textMuted, size: 64),
              SizedBox(height: 16),
              Text('Search for music', style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Searches',
                    style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(searchHistoryProvider.notifier).clearHistory(),
                    child: Text('Clear All', style: TextStyle(color: ThemeTokens.of(context).accent, fontSize: 13)),
                  ),
                ],
              ),
            );
          }

          final query = history[index - 1];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.history_rounded, color: ThemeTokens.of(context).textMuted, size: 22),
            title: Text(query, style: TextStyle(color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
            trailing: IconButton(
              icon: Icon(Icons.close_rounded, color: ThemeTokens.of(context).textMuted, size: 18),
              onPressed: () => ref.read(searchHistoryProvider.notifier).removeQuery(query),
            ),
            onTap: () {
              onTap(query);
            },
          );
        },
        childCount: history.length + 1,
      ),
    );
  }
}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SearchHeaderDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: ThemeTokens.of(context).bgBase.withOpacity(shrinkOffset > 0 ? 0.9 : 0.0),
      child: child,
    );
  }

  @override
  double get maxExtent => 64;
  @override
  double get minExtent => 64;
  @override
  bool shouldRebuild(_SearchHeaderDelegate old) => old.child != child;
}

class _SearchResultsSliver extends ConsumerWidget {
  final String query;
  const _SearchResultsSliver({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(searchProvider(query));

    return searchAsync.when(
      data: (results) {
        final songs = results['songs'] as List<dynamic>? ?? [];
        if (songs.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sentiment_dissatisfied_rounded, color: ThemeTokens.of(context).textMuted, size: 48),
                  SizedBox(height: 12),
                  Text('No results found', style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 15)),
                ],
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final song = songs[index];
              return SongTile(
                song: song,
                onTap: () {
                  ref.read(searchHistoryProvider.notifier).addQuery(query);
                  ref.read(playerProvider.notifier).setQueue(songs.cast(), index);
                },
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
            },
            childCount: songs.length,
          ),
        );
      },
      loading: () => SliverFillRemaining(
        child: Center(child: CircularProgressIndicator(color: ThemeTokens.of(context).accent)),
      ),
      error: (e, st) => SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              SizedBox(height: 12),
              Text('Error: $e', style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
