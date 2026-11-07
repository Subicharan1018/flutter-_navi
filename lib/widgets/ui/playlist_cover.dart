import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/playlist.dart';
import '../../providers/settings_provider.dart';
import '../art/navi_icons.dart';
import 'mosaic_art.dart';

/// The covers of the first songs of a playlist (up to four, each different), for
/// a playlist that has no cover of its own. Fetched once per playlist (the
/// service caches the song list) and kept for the session.
final playlistMosaicProvider = FutureProvider.family<List<String>, String>((ref, playlistId) async {
  final link = ref.keepAlive();
  try {
    final songs = await ref.watch(subsonicServiceProvider).getPlaylistSongs(playlistId);
    final ids = <String>[];
    for (final s in songs) {
      final c = s.coverArt.isNotEmpty ? s.coverArt : s.id;
      if (!ids.contains(c)) ids.add(c);
      if (ids.length == 4) break;
    }
    return ids;
  } catch (_) {
    link.close(); // a failed fetch is tried again next time it is drawn
    return const [];
  }
});

/// A playlist's artwork: its own cover when the server has one, otherwise a 2×2
/// mosaic of the first four songs' covers (one cover if it has fewer than four),
/// and the playlist glyph only while those load or when it is empty.
///
/// Inside a desktop shelf it takes the shelf's tile size ([ShelfSize]); [size] is
/// used everywhere else.
class PlaylistCover extends ConsumerWidget {
  final Playlist playlist;
  final double size;
  final double radius;

  /// A thumbnail too small for four covers to read (a 40 px list row, the rail's
  /// 40 px rows): the first song's cover alone, so it is one picture, not stripes.
  final bool compact;
  const PlaylistCover({super.key, required this.playlist, required this.size, this.radius = Radii.cover, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ShelfSize.of(context) ?? size;
    final svc = ref.read(subsonicServiceProvider);
    if ((playlist.coverArt ?? '').isNotEmpty) {
      return MosaicArt(urls: [svc.getCoverArtUrl(playlist.coverArt)], size: s, radius: radius, placeholderIcon: NaviGlyph.playlist);
    }
    final all = ref.watch(playlistMosaicProvider(playlist.id)).asData?.value ?? const <String>[];
    final ids = compact && all.isNotEmpty ? all.take(1).toList() : all;
    return MosaicArt(
      urls: [for (final id in ids) svc.getCoverArtUrl(id)],
      size: s,
      radius: radius,
      placeholderIcon: NaviGlyph.playlist,
    );
  }
}
