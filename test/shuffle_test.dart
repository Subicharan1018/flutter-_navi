import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/audio_handler.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:just_audio/just_audio.dart';

class TestAudioHandler extends AudioHandler {
  TestAudioHandler(super.subsonicService, {super.player});

  bool updateSourceCalled = false;

  @override
  Future<void> _updatePlayerSource(int startIndex) async {
    updateSourceCalled = true;
  }
}

class MockSubsonicService extends SubsonicService {
  MockSubsonicService() : super(serverUrl: '', username: '', password: '');
}

class MockAudioPlayer extends Fake implements AudioPlayer {
  @override
  int? get currentIndex => 0;

  @override
  AudioSource? get audioSource => null;

  @override
  Future<Duration?> setAudioSource(AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    return null;
  }
}

void main() {
  group('Balanced Shuffle Logic', () {
    late TestAudioHandler handler;
    late Song s1, s2, s3, s4;

    setUp(() {
      final mockService = MockSubsonicService();
      final mockPlayer = MockAudioPlayer();
      handler = TestAudioHandler(mockService, player: mockPlayer);

      s1 = Song(id: '1', title: 'S1', artist: 'A1', album: 'B1', composer: 'Comp1', genre: 'G1', coverArt: '', duration: 100, track: 1, year: 2020);
      s2 = Song(id: '2', title: 'S2', artist: 'A2', album: 'B2', composer: 'Comp1', genre: 'G2', coverArt: '', duration: 100, track: 2, year: 2020);
      s3 = Song(id: '3', title: 'S3', artist: 'A3', album: 'B3', composer: 'Comp2', genre: 'G1', coverArt: '', duration: 100, track: 3, year: 2020);
      s4 = Song(id: '4', title: 'S4', artist: 'A4', album: 'B4', composer: 'Comp2', genre: 'G2', coverArt: '', duration: 100, track: 4, year: 2020);

      handler.currentQueue = [s1, s2, s3, s4];
    });

    test('Groups correctly by Composer when preference is composer', () {
      handler.spotifyDitherShuffle(ShufflePreference.composer);

      final result = handler.currentQueue;
      expect(result[0].id, '1');
      // S1 is Comp1. result[1] MUST be Comp2 (S3 or S4)
      expect(result[1].composer, 'Comp2');
    });

    test('Groups correctly by Genre when preference is genre', () {
      handler.spotifyDitherShuffle(ShufflePreference.genre);

      final result = handler.currentQueue;
      expect(result[0].id, '1');
      // S1 is G1. result[1] MUST be G2 (S2 or S4)
      expect(result[1].genre, 'G2');
    });

    test('Handles missing metadata gracefully with "Unknown" bucket', () {
      final s5 = Song(id: '5', title: 'S5', artist: 'A5', album: 'B5', composer: '', genre: '', coverArt: '', duration: 100, track: 5, year: 2020);
      handler.currentQueue = [s1, s5];

      handler.spotifyDitherShuffle(ShufflePreference.composer);
      expect(handler.currentQueue.length, 2);
      expect(handler.currentQueue[1].id, '5');
    });
  });

  test('Song.fromJson parses displayComposer', () {
    final json = {
      'id': '1',
      'title': 'Test Title',
      'displayComposer': 'Beethoven',
      'genre': 'Classical',
    };
    final song = Song.fromJson(json);
    expect(song.composer, 'Beethoven');
  });
}
