import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/album.dart';
import '../../../providers/settings_provider.dart' show appDatabaseProvider;

/// One finished play of a song by the artist (a play that was not skipped
/// before half way), as read from the on-device play log.
class ArtistPlay {
  final String song;
  final String album;
  final DateTime at;
  final int seconds;
  const ArtistPlay({required this.song, required this.album, required this.at, required this.seconds});
}

/// What the listener's own play log says about one artist. Everything here is
/// counted from real plays; nothing is estimated.
class ArtistHistory {
  final int plays;
  final int minutes;
  final DateTime? first;
  final DateTime? last;
  final String? topSong;
  final int topSongPlays;

  /// Finished plays per album, keyed by lower-cased album name.
  final Map<String, int> albumPlays;

  const ArtistHistory({
    this.plays = 0,
    this.minutes = 0,
    this.first,
    this.last,
    this.topSong,
    this.topSongPlays = 0,
    this.albumPlays = const {},
  });

  bool get isEmpty => plays == 0;

  /// Plays of [album] (matched by name; the log stores names, not ids).
  int playsOf(Album album) => albumPlays[album.name.trim().toLowerCase()] ?? 0;

  factory ArtistHistory.from(Iterable<ArtistPlay> events) {
    var plays = 0;
    var seconds = 0;
    DateTime? first;
    DateTime? last;
    final songs = <String, int>{};
    final albums = <String, int>{};
    for (final e in events) {
      plays++;
      seconds += e.seconds;
      if (first == null || e.at.isBefore(first)) first = e.at;
      if (last == null || e.at.isAfter(last)) last = e.at;
      songs.update(e.song, (n) => n + 1, ifAbsent: () => 1);
      albums.update(e.album.trim().toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }
    String? top;
    var topN = 0;
    songs.forEach((s, n) {
      if (n > topN || (n == topN && top != null && s.compareTo(top!) < 0)) {
        top = s;
        topN = n;
      }
    });
    return ArtistHistory(
      plays: plays,
      minutes: (seconds / 60).round(),
      first: first,
      last: last,
      topSong: top,
      topSongPlays: topN,
      albumPlays: albums,
    );
  }
}

/// The finished plays of [artist], newest data first not required: the
/// aggregate does not depend on order. One query, no stream: the page reads it
/// when it opens.
final artistHistoryProvider = FutureProvider.autoDispose.family<ArtistHistory, String>((ref, artist) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db
      .customSelect(
        'SELECT m.track_name AS song, m.album_name AS album, p.ts_start AS at, p.play_dur_sec AS secs '
        'FROM play_events p JOIN song_metadata m ON m.song_id = p.song_id '
        'WHERE lower(m.artist_name) = lower(?1) AND p.skip_before50 = 0',
        variables: [Variable.withString(artist.trim())],
      )
      .get();
  return ArtistHistory.from([
    for (final r in rows)
      ArtistPlay(
        song: r.read<String>('song'),
        album: r.read<String>('album'),
        at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('at')),
        seconds: r.read<int>('secs'),
      ),
  ]);
});

/// The albums released in one year (0 = no year recorded).
class ReleaseYear {
  final int year;
  final List<Album> albums;
  const ReleaseYear(this.year, this.albums);

  int get songs => albums.fold(0, (n, a) => n + a.songCount);
}

/// Groups albums by release year, newest year first; albums with no year come
/// last as year 0. Within a year the order the server gave is kept.
List<ReleaseYear> groupByYear(Iterable<Album> albums) {
  final byYear = <int, List<Album>>{};
  for (final a in albums) {
    byYear.putIfAbsent(a.year > 0 ? a.year : 0, () => []).add(a);
  }
  final years = byYear.keys.toList()..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : b.compareTo(a)));
  return [for (final y in years) ReleaseYear(y, byYear[y]!)];
}
