import 'album.dart';
import 'artist.dart';
import 'song.dart';

/// What one search returns, grouped the way the Search screen shows it.
class SearchResults {
  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  const SearchResults({this.artists = const [], this.albums = const [], this.songs = const []});

  static const empty = SearchResults();

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}
