import 'dart:math';

import '../../models/album.dart';
import '../../models/song.dart';

/// R10: "Albums for you" and "Shuffle by album". Pure logic.

/// An album with its songs, as the server describes them.
class AlbumCandidate {
  const AlbumCandidate(this.album, this.songs);
  final Album album;
  final List<Song> songs;
}

/// An album worth offering: you love part of it and haven't heard the rest.
class AlbumPick {
  const AlbumPick({
    required this.album,
    required this.loved,
    required this.unheard,
    required this.total,
    required this.lovedTitle,
    required this.score,
  });

  final Album album;
  final int loved;
  final int unheard;
  final int total;

  /// A song of it you love: "Because you love Vaseegara".
  final String lovedTitle;
  final double score;

  String get reason => loved > 1
      ? 'You love $lovedTitle and ${loved - 1} more · $unheard to discover'
      : 'You love $lovedTitle · $unheard more to discover';
}

/// Play count from which a song counts as loved, with a star or a high rating.
const lovedPlayCount = 5;

bool isLoved(Song s) => s.starred || s.rating >= 4 || s.playCount >= lovedPlayCount;

/// Albums where you love one or two songs and haven't heard the rest.
///
/// An album counts when it has at least [minSongs] songs, at least one loved
/// song but no more than half of it loved (an album you love end to end needs
/// no suggestion), and at least [minUnheard] songs (and 40 % of it) that you
/// never played. [playedLocally] lists song ids this device has heard even if
/// the server's count has not caught up. [hidden] holds album ids the listener
/// dismissed. Best first, at most [max].
List<AlbumPick> albumsForYou(
  Iterable<AlbumCandidate> candidates, {
  Set<String> playedLocally = const {},
  Set<String> hidden = const {},
  int minSongs = 5,
  int minUnheard = 3,
  int max = 12,
}) {
  final picks = <AlbumPick>[];
  for (final c in candidates) {
    if (hidden.contains(c.album.id)) continue;
    final songs = c.songs;
    if (songs.length < minSongs) continue;
    final lovedSongs = songs.where(isLoved).toList();
    if (lovedSongs.isEmpty || lovedSongs.length * 2 > songs.length) continue;
    final unheard = songs.where((s) => !isLoved(s) && s.playCount == 0 && !playedLocally.contains(s.id)).length;
    if (unheard < minUnheard || unheard < songs.length * 0.4) continue;
    final favourite = (lovedSongs.toList()..sort((a, b) => b.playCount.compareTo(a.playCount))).first;
    picks.add(AlbumPick(
      album: c.album,
      loved: lovedSongs.length,
      unheard: unheard,
      total: songs.length,
      lovedTitle: favourite.title,
      score: min(lovedSongs.length, 3) + 3 * unheard / songs.length,
    ));
  }
  picks.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.album.name.compareTo(b.album.name);
  });
  return picks.take(max).toList();
}

/// Whole albums, in random order, each in track order.
///
/// Songs are grouped by album (the id, or name and artist when there is no
/// id); inside an album they follow the disc/track order given by `track`,
/// ties keeping their incoming order. A song with no album stands alone.
/// The albums' order comes from [random].
List<Song> shuffleByAlbum(List<Song> songs, Random random) {
  final groups = <String, List<(int, Song)>>{};
  var loose = 0;
  for (var i = 0; i < songs.length; i++) {
    final s = songs[i];
    final key = s.albumId.isNotEmpty
        ? 'id:${s.albumId}'
        : (s.album.isNotEmpty && s.album != 'Unknown Album' ? 'n:${s.album.toLowerCase()}|${s.artist.toLowerCase()}' : 'solo:${loose++}');
    groups.putIfAbsent(key, () => []).add((i, s));
  }
  final albums = groups.values.toList()..shuffle(random);
  return [
    for (final g in albums)
      ...(g
            ..sort((a, b) {
              // Songs without a track number keep their incoming order, after numbered ones.
              final ta = a.$2.track > 0 ? a.$2.track : 1 << 30;
              final tb = b.$2.track > 0 ? b.$2.track : 1 << 30;
              final c = ta.compareTo(tb);
              return c != 0 ? c : a.$1.compareTo(b.$1);
            }))
          .map((e) => e.$2),
  ];
}
