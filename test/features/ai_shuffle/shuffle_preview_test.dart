import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/next_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';

RecommendedSong _rec(String title) => RecommendedSong(
      rank: 1,
      title: title,
      filePath: 'path/$title.mp3',
      genreBucket: 'Pop',
      composer: 'Artist',
      audio: const AudioFeatures(energy: 0.5, valence: 0.5, acousticness: 0.5, danceability: 0.5),
      scores: const SongScores(contextHistory: 0.5, audioFit: 0.5, composerLoyalty: 0.5, finalScore: 0.5),
      why: '',
      artist: 'Artist',
      album: 'Album',
    );

/// Records what the notifier asks the server for.
class _FakeRepo extends Fake implements ShuffleRepository {
  List<String> lastExcluded = const [];
  int impressionPosts = 0;

  @override
  Future<NextResponse> getNext({
    String source = 'smart',
    String? playlistId,
    int count = 15,
    int depth = 0,
    String? playlistName,
    String genreStreakType = '',
    int genreStreakCount = 0,
    List<String> playedTitles = const [],
    List<double> recentListenRatios = const [],
    String lastEndReason = '',
    List<String> candidates = const [],
    bool reshuffle = false,
    List<String> excludedTitles = const [],
    String seedTitle = '',
  }) async {
    lastExcluded = excludedTitles;
    return NextResponse(mode: 'smart', source: source, queue: [_rec('Fresh')]);
  }

  @override
  Future<void> postImpressions({required List<String> shown, required List<String> played}) async {
    impressionPosts++;
  }
}

void main() {
  group('Smart Shuffle preview', () {
    test('clearing the preview keeps the playing mix’s session alive', () {
      final notifier = ShuffleQueueNotifier(_FakeRepo())..initSession();
      final session = notifier.sessionId;

      // Opening the Smart Shuffle screen used to call clearQueue(), which
      // ended the session of a mix that was already playing.
      notifier.clearPreview();

      expect(notifier.hasActiveSession, isTrue);
      expect(notifier.sessionId, session);
    });

    test('reshuffle bans the songs already on screen', () async {
      final repo = _FakeRepo();
      final notifier = ShuffleQueueNotifier(repo);

      await notifier.reshuffle(visibleTitles: const ['Midnight City', 'Espresso']);

      expect(repo.lastExcluded, containsAll(['Midnight City', 'Espresso']));
      expect(notifier.state.allRecommendedSongs.single.title, 'Fresh');
    });
  });
}
