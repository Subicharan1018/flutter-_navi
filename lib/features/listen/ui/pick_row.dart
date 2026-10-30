import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/options_menu.dart' show showSongActions;
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../logic/listen_providers.dart';

/// Opens the song actions sheet for a server pick, once its library song loads.
Future<void> showPickActions(BuildContext context, WidgetRef ref, String songId) async {
  List<Song> songs = const [];
  try {
    songs = await ref.read(listenSongsProvider).load([songId]);
  } catch (_) {}
  if (!context.mounted) return;
  if (songs.isEmpty) {
    showToast(context, 'Couldn’t load this song. Check your connection and try again.');
    return;
  }
  await showSongActions(context, songs.first);
}

/// One song the server picked: cover, title, artist, and the line saying why
/// it's here. The ⋯ opens the song's actions (Never recommend among them).
class PickRow extends ConsumerWidget {
  static const double cover = 52;

  final String songId;
  final String title;
  final String artist;

  /// The reason it's here; a second, quieter line.
  final String? why;

  /// A small label before the artist ("New", "Familiar").
  final String? tag;

  /// A song in a language you rarely play: marked with a sparkle before its reason.
  final bool explore;
  final VoidCallback onTap;
  final bool showSeparator;

  const PickRow({
    super.key,
    required this.songId,
    required this.title,
    required this.artist,
    required this.onTap,
    this.why,
    this.tag,
    this.explore = false,
    this.showSeparator = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final art = ref.read(subsonicServiceProvider).getCoverArtUrl(songId);
    final subtitle = [?tag, artist].where((s) => s.isNotEmpty).join(' · ');
    return CupertinoClickable(
      onTap: onTap,
      onLongPress: () => showPickActions(context, ref, songId),
      scaleFactor: 0.99,
      semanticLabel: [title, subtitle, ?why].join(', '),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.gutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: CoverArt(url: art, size: cover, radius: Radii.thumb),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: cover + Space.lg),
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                decoration: BoxDecoration(
                  border: showSeparator ? Border(bottom: BorderSide(color: t.outline, width: 0.5)) : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                          if (subtitle.isNotEmpty)
                            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                          if (why != null && why!.isNotEmpty) ...[
                            const SizedBox(height: Space.xxs),
                            Text.rich(
                              TextSpan(children: [
                                // A new-language song is marked by a small sparkle, nothing louder.
                                if (explore)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: Space.xs),
                                      child: NaviIcon(NaviGlyph.smart, size: 12, color: t.textSecondary),
                                    ),
                                  ),
                                TextSpan(text: why!),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.footnote.copyWith(color: t.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    CupertinoClickable(
                      onTap: () => showPickActions(context, ref, songId),
                      semanticLabel: 'More for $title',
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(child: NaviIcon(NaviGlyph.more, size: 20, color: t.textSecondary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
