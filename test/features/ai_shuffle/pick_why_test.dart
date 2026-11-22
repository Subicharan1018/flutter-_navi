import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/recommended_song.dart';
import 'package:navivibe/features/ai_shuffle/logic/pick_why.dart';

RecommendedSong rec({
  double history = 0,
  double fit = 0,
  double composerScore = 0,
  String composer = '',
  bool starter = false,
  bool explore = false,
  SongPairing? pairing,
  double? loyalty,
  int? daysSincePlay,
  String why = '',
}) =>
    RecommendedSong(
      rank: 1,
      title: 'T',
      filePath: '',
      genreBucket: '',
      composer: composer,
      audio: const AudioFeatures(energy: .5, valence: .5, acousticness: .5, danceability: .5),
      scores: SongScores(contextHistory: history, audioFit: fit, composerLoyalty: composerScore, finalScore: .5),
      why: why,
      isStarter: starter,
      isExplore: explore,
      pairing: pairing,
      loyalty: loyalty,
      daysSincePlay: daysSincePlay,
    );

void main() {
  test('a song you play at moments like this says so', () {
    final w = pickWhy(rec(history: .7));
    expect(w.short, 'You play it now');
    expect(w.reasons.single, contains('moments like this'));
  });

  test('a weaker history is claimed more modestly', () {
    expect(pickWhy(rec(history: .3)).short, 'You’ve played it now');
  });

  test('below every threshold nothing is claimed; the server’s words are used', () {
    final w = pickWhy(rec(history: .1, fit: .2, why: 'Matches the evening calm'));
    expect(w.short, 'Matches the evening calm');
  });

  test('nothing known at all falls back to a plain line', () {
    expect(identical(pickWhy(rec()), PickWhy.generic), isTrue);
  });

  test('the usual follower names the song it follows and how often', () {
    final w = pickWhy(rec(pairing: const SongPairing(follows: 'Kanne Kanne', timesFollowed: 4, probability: .4)));
    expect(w.short, 'Follows “Kanne Kanne”');
    expect(w.reasons.single, 'You usually play it after “Kanne Kanne” (4 times).');
  });

  test('composer loyalty needs a composer name', () {
    expect(pickWhy(rec(composerScore: .9)).reasons, ['Fits your taste overall.']);
    expect(pickWhy(rec(composerScore: .9, composer: 'A. R. Rahman')).reasons.single,
        'By A. R. Rahman, a composer you keep returning to.');
  });

  test('several reasons are listed strongest first and the table gets the first', () {
    final w = pickWhy(rec(starter: true, history: .8, fit: .9, explore: false));
    expect(w.short, 'Your usual opener');
    expect(w.reasons.length, 3);
  });

  test('a long gap and a new song are said plainly', () {
    expect(pickWhy(rec(daysSincePlay: 90)).short, 'Back after 90 days');
    expect(pickWhy(rec(daysSincePlay: 10)).reasons, ['Fits your taste overall.']);
    expect(pickWhy(rec(explore: true)).short, 'New to you');
  });
}
