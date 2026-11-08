import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/navi_icon_button.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import '../logic/online_fetch_providers.dart';
import 'fetch_queue_sheet.dart';
import 'online_search_sheet.dart';
import 'send_playlist_sheet.dart';

/// "Search online" on Windows: a page in the window, not a phone sheet. A search
/// field and the kind of result in one toolbar, the results as a table below
/// (hover, right-click, Enter), the download queue and "Send a playlist" at the
/// top right. F5 searches again; Esc steps back out of an artist's songs.
class OnlineSearchPage extends ConsumerStatefulWidget {
  final String query;
  const OnlineSearchPage({super.key, required this.query});

  @override
  ConsumerState<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends ConsumerState<OnlineSearchPage> {
  late final _field = TextEditingController(text: widget.query);
  FetchSearchType _type = FetchSearchType.song;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(widget.query));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _search(String query) {
    final q = query.trim();
    if (q.length < 2) return;
    _field.text = q;
    unawaited(ref.read(onlineSearchProvider.notifier).start(q, type: _type));
  }

  void _setType(FetchSearchType type) {
    setState(() => _type = type);
    _search(_field.text);
  }

  Future<void> _play(Future<Song> Function() load) async {
    try {
      final song = await load();
      if (!mounted) return;
      await ref.read(playerProvider.notifier).setQueue([song], 0, playlistName: 'Search');
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(e is OnlineFetchException ? e.message : 'Couldn’t start playback. Try again.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(onlineSearchProvider);
    final inArtist = s.artist != null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () => _search(s.query.isEmpty ? _field.text : s.query),
        if (inArtist) const SingleActivator(LogicalKeyboardKey.escape): () => ref.read(onlineSearchProvider.notifier).back(),
      },
      child: Focus(
        child: LargeTitlePage(
          title: 'Search online',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NaviIconButton(
                glyph: NaviGlyph.queue,
                tooltip: 'Download queue',
                box: 40,
                onTap: () => showFetchQueue(context),
              ),
              const SizedBox(width: Space.sm),
              TintedButton(
                glyph: NaviGlyph.link,
                label: 'Send a playlist',
                height: 36,
                onTap: () => showSendPlaylist(context),
              ),
            ],
          ),
          slivers: [
            PageSliver(
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Finds music that isn’t in your library and adds it in lossless quality.', style: t.footnote),
                    const SizedBox(height: Space.md),
                    if (!inArtist)
                      Wrap(
                        spacing: Space.lg,
                        runSpacing: Space.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 440,
                            child: NaviSearchField(
                              controller: _field,
                              placeholder: _type.placeholder,
                              onSubmitted: _search,
                              autofocus: true,
                            ),
                          ),
                          SizedBox(
                            width: 420,
                            child: NaviSegmented<FetchSearchType>(
                              segments: {for (final ty in FetchSearchType.values) ty: ty.title},
                              value: _type,
                              onChanged: _setType,
                            ),
                          ),
                        ],
                      )
                    else
                      OnlineArtistHeader(state: s),
                    const SizedBox(height: Space.md),
                    const ActiveFetchDownloads(),
                    OnlineSearchBody(state: s, onSearch: _search, onPlay: _play),
                    const SizedBox(height: Space.xl),
                  ],
                ),
              ),
            ),
          ],
          clearPlayer: false,
        ),
      ),
    );
  }
}
