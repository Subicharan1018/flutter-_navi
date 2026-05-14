import 'package:navivibe/models/song.dart';

/// Helper to create a dummy song for testing
Song makeSong({
  String id = 'song-1',
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
  String genre = 'Unknown',
  String composer = 'Unknown',
  String coverArt = '',
  int duration = 180,
  int track = 1,
  int year = 2024,
  bool starred = false,
  int playCount = 0,
  int rating = 0,
  double dynamicWeight = 1.0,
}) {
  return Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    composer: composer,
    coverArt: coverArt,
    duration: duration,
    track: track,
    year: year,
    starred: starred,
    playCount: playCount,
    rating: rating,
    dynamicWeight: dynamicWeight,
    albumId: 'album-1',
    artistId: 'artist-1',
  );
}

/// Helper to advance the microtask queue
Future<void> pumpMicrotasks() => Future.delayed(Duration.zero);
