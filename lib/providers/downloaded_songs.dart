import '../models/library_sort.dart';
import '../models/song.dart';

/// The Downloaded list: every id the device holds, described by the library
/// mirror where it knows the song, else by the metadata saved beside the
/// audio file, else by a bare entry. Nothing downloaded is ever left out,
/// whatever state the mirror (or the server) is in.
///
/// [mirror] and [disk] may overlap; the mirror wins because it is the fresher
/// copy. Order follows [ids] for the entries without a mirror row.
List<Song> mergeDownloadedSongs({
  required Set<String> ids,
  required List<Song> mirror,
  required List<Song> disk,
  String query = '',
}) {
  final byId = <String, Song>{
    for (final s in disk)
      if (ids.contains(s.id)) s.id: s,
    for (final s in mirror)
      if (ids.contains(s.id)) s.id: s,
  };
  final songs = <Song>[
    for (final id in ids)
      byId[id] ?? Song(id: id, title: 'Downloaded song', artist: '', album: '', duration: 0, coverArt: id, track: 0, year: 0),
  ];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return songs;
  return [
    for (final s in songs)
      if (s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q)) s,
  ];
}

/// [songs] ordered by a library sort preference (same fields as the database
/// query the other lists use).
List<Song> sortSongs(List<Song> songs, LibrarySortPreference pref) {
  int byField(Song a, Song b) => switch (pref.field) {
        LibrarySortField.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        LibrarySortField.artistName => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        LibrarySortField.duration => a.duration.compareTo(b.duration),
        LibrarySortField.playCount => a.playCount.compareTo(b.playCount),
        LibrarySortField.recentlyAdded =>
          (a.created ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.created ?? DateTime.fromMillisecondsSinceEpoch(0)),
      };
  final sorted = [...songs]..sort(byField);
  return pref.direction == LibrarySortDirection.asc ? sorted : sorted.reversed.toList();
}
