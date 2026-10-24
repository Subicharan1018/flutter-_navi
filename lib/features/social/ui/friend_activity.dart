import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/media.dart';
import '../data/social_models.dart';
import '../logic/social_providers.dart';
import '../../../widgets/art/empty_art.dart' show EmptyArtKind;
import 'social_widgets.dart';

/// "What are my friends playing" — now playing first, then each person's
/// latest plays. Shows nothing until this person has turned friend activity on.
class FriendActivitySection extends ConsumerWidget {
  const FriendActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(socialEnabledProvider);
    if (!enabled) return const SizedBox.shrink();
    final feed = ref.watch(friendFeedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Friends'),
        feed.when(
          loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CupertinoActivityIndicator())),
          error: (_, _) => SocialNote(
            glyph: NaviGlyph.group,
            title: 'Couldn’t load friends',
            message: 'Check your connection to the server, then try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(friendFeedProvider),
          ),
          data: (data) => data.friends.isEmpty
              ? const SocialNote(
                  glyph: NaviGlyph.group,
                  art: EmptyArtKind.record,
                  title: 'No one is playing right now',
                  message: 'Friends who turned on social features show up here when they listen.',
                )
              : Column(children: [
                  for (final (i, f) in data.friends.indexed)
                    _FriendRow(friend: f, showSeparator: i < data.friends.length - 1),
                ]),
        ),
      ],
    );
  }
}

Song _songOf(FriendSong s) => Song.fromJson({
      'id': s.songId,
      'title': s.title,
      'artist': s.artist,
      'album': s.album,
      'coverArt': s.coverArt,
    });

class _FriendRow extends ConsumerWidget {
  final FriendActivity friend;
  final bool showSeparator;
  const _FriendRow({required this.friend, required this.showSeparator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final svc = ref.read(subsonicServiceProvider);
    final now = friend.nowPlaying;
    final shown = now ?? (friend.recent.isEmpty ? null : friend.recent.first);
    final line = switch ((now, shown)) {
      (final n?, _) => n.artist.isEmpty ? n.title : '${n.title} · ${n.artist}',
      (_, final r?) => r.title,
      _ => '',
    };
    final caption = now != null
        ? (now.minutesAgo == null || now.minutesAgo == 0 ? 'Listening now' : '${now.minutesAgo} min ago')
        : 'Recently played';

    return CupertinoClickable(
      onTap: shown != null && shown.playable
          ? () => ref.read(playerProvider.notifier).setQueue([_songOf(shown)], 0)
          : null,
      scaleFactor: 0.99,
      semanticLabel: '${friend.username}, $caption, $line',
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
        decoration: showSeparator
            ? BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5)))
            : null,
        child: Row(children: [
          PersonAvatar(friend.username),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(friend.username, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(line, style: t.subheadline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(caption, style: t.footnote),
            ]),
          ),
          if (shown != null && shown.coverArt.isNotEmpty) ...[
            const SizedBox(width: Space.md),
            CoverArt(url: svc.getCoverArtUrl(shown.coverArt), size: 44, radius: Radii.thumb),
          ],
        ]),
      ),
    );
  }
}
