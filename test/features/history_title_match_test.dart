import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/logic/recommendation_resolver.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/utils/history_title_key.dart';

Song song(String id, String title, {String artist = 'Anirudh Ravichander'}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: 'Al',
      coverArt: 'c$id',
      duration: 100,
      track: 1,
      year: 2025,
    );

void main() {
  final library = [
    song('monica', 'Monica (From "Coolie")'),
    song('oorum', 'Oorum Blood (From "Dude")'),
    song('oorumU', 'Oorum Blood Unplugged'),
    song('pathi', 'Pathikichu'),
  ];
  final r = RecommendationResolver(library);

  String? id(String title, [String artist = '']) => r.match(title, artist)?.id;

  test('film and language tags in history titles still find the song', () {
    expect(id('Monica (From "Coolie") (Tamil)'), 'monica');
    expect(id('Monica'), 'monica');
    expect(id('Oorum Blood'), 'oorum');
    expect(id('Pathikichu (From "Vidaamuyarchi")'), 'pathi');
    expect(id('Pathikichu'), 'pathi');
    expect(id('Monica - TAMIL'), 'monica');
    expect(id('Monica (From “Coolie”) [Tamil]'), 'monica');
  });

  test('distinct versions never merge with the plain song', () {
    expect(id('Oorum Blood Unplugged'), 'oorumU');
    final plainOnly = RecommendationResolver([song('a', 'Oorum Blood Unplugged')]);
    expect(plainOnly.match('Oorum Blood', ''), isNull);
    final versions = [
      'Unplugged', 'Orchestral', 'Rage Rock', 'Soul', 'Remix', 'Live',
      'Instrumental', 'Karaoke', 'Reprise', 'Slowed', 'Sped up',
    ];
    for (final v in versions) {
      final lib = RecommendationResolver([song('v', 'Pathikichu ($v)')]);
      expect(lib.match('Pathikichu', ''), isNull, reason: v);
      expect(lib.match('Pathikichu (From "X") ($v)', '')?.id, 'v', reason: v);
      final plain = RecommendationResolver([song('p', 'Pathikichu')]);
      expect(plain.match('Pathikichu ($v)', ''), isNull, reason: v);
    }
  });

  test('artist breaks ties between same-key songs', () {
    final two = RecommendationResolver([
      song('x', 'Hero (From "A")', artist: 'Alpha'),
      song('y', 'Hero (From "B")', artist: 'Beta'),
    ]);
    expect(two.match('Hero (Tamil)', 'Beta')?.id, 'y');
  });

  test('exact title still wins over normalised match', () {
    final lib = RecommendationResolver([
      song('tag', 'Monica (From "Coolie")'),
      song('plain', 'Monica'),
    ]);
    expect(lib.match('Monica', '')?.id, 'plain');
  });

  test('featured-artist tags are ignored', () {
    final lib = RecommendationResolver([song('m', 'Munbe Vaa')]);
    expect(lib.match('Munbe Vaa (From "S") [feat. Bright Joshua]', '')?.id, 'm');
    expect(lib.match('Munbe Vaa (feat. X)', '')?.id, 'm');
  });

  test('historyTitleKey', () {
    expect(historyTitleKey('Monica (From "Coolie") (Tamil)'), 'monica');
    expect(historyTitleKey('Song (Remix)'), 'songremix');
  });
}
