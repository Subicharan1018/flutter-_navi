import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/feedback_request.dart';
import 'package:navivibe/features/ai_shuffle/data/models/next_response.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';

/// A Smart Shuffle server stand-in for player tests: answers /next with the
/// candidates in reverse order, so the Smart Local path runs end to end and
/// deterministically, with no network (the test binding turns every real
/// HTTP request into a 400, which silently exercised the offline fallback).
class ReversingShuffleRepository extends Fake implements ShuffleRepository {
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
    return NextResponse(
      mode: 'smart',
      source: source,
      queue: [
        for (final (i, title) in candidates.reversed.indexed)
          RecommendedSong(
            rank: i + 1,
            title: title,
            filePath: 'path/$title',
            genreBucket: 'Rock',
            composer: 'Artist',
            audio: const AudioFeatures(energy: 0.5, valence: 0.5, acousticness: 0.5, danceability: 0.5),
            scores: const SongScores(contextHistory: 0.5, audioFit: 0.5, composerLoyalty: 0.5, finalScore: 0.5),
            why: '',
            artist: 'Artist',
            album: 'Album',
          ),
      ],
    );
  }

  @override
  Future<void> postFeedback(FeedbackRequest request) async {}

  @override
  Future<void> postImpressions({required List<String> shown, required List<String> played}) async {}
}
