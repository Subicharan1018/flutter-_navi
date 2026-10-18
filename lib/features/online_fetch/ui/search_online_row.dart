import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/media.dart';
import '../data/fetch_models.dart';
import '../logic/online_fetch_providers.dart';
import 'online_search_sheet.dart';
import 'send_playlist_sheet.dart';

/// Under the library results: "Can't find it? Search online", and the other
/// way in, "Send a playlist link". A pasted link goes straight to the latter.
/// Renders nothing unless the server allows this account to search online.
class SearchOnlineRow extends ConsumerWidget {
  final String query;
  const SearchOnlineRow({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(onlineFetchEnabledProvider).asData?.value ?? false;
    if (!enabled) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final isLink = looksLikeLink(query);
    return Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.lg),
      child: Column(
        children: [
          if (!isLink)
            CollectionRow(
              title: 'Search online for “$query”',
              subtitle: 'Can’t find it? Add it to your library',
              leading: Icon(CupertinoIcons.globe, size: 22, color: t.accent),
              titleColor: t.accent,
              onTap: () => showOnlineSearch(context, query),
            ),
          CollectionRow(
            title: isLink ? 'Send this playlist link' : 'Send a playlist link',
            subtitle: 'Deezer or Spotify: add its songs as a playlist',
            leading: Icon(CupertinoIcons.link, size: 22, color: t.accent),
            titleColor: t.accent,
            showSeparator: false,
            onTap: () => showSendPlaylist(context, link: isLink ? query : null),
          ),
        ],
      ),
    );
  }
}
