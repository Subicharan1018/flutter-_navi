import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/data/models/intent_response.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_exception.dart';
import 'package:navivibe/features/ai_shuffle/logic/mix_intent_provider.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/models/song.dart';

import '../../helpers/reversing_shuffle_repository.dart';

/// /next answers with the candidates reversed; /intent answers from [reply].
class _IntentRepo extends ReversingShuffleRepository {
  final Object reply; // IntentResponse or an exception to throw
  final asked = <String>[];
  _IntentRepo(this.reply);

  @override
  Future<IntentResponse> interpretIntent(String text) async {
    asked.add(text);
    if (reply is Exception) throw reply as Exception;
    return reply as IntentResponse;
  }
}

ProviderContainer _container(_IntentRepo repo) {
  final c = ProviderContainer(overrides: [shuffleRepositoryProvider.overrideWithValue(repo)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('parses the server answer, with friendly loosened labels', () {
    final r = IntentResponse.fromJson({
      'summary': 'A.R. Rahman · 1990s', 'candidates': ['Roja', 'Bombay Theme'], 'count': 2,
      'relaxed': ['years', 'mood'], 'ai': false, 'understood': true,
    });
    expect(r.candidates, ['Roja', 'Bombay Theme']);
    expect(r.relaxed, ['era', 'mood']);
  });

  test('a described mix loads a /next batch from only the songs that fit', () async {
    final repo = _IntentRepo(const IntentResponse(
      summary: 'Tamil · Melody · calm', candidates: ['A', 'B', 'C'], count: 3));
    final c = _container(repo);

    await c.read(mixIntentProvider.notifier).apply('  calm Tamil melodies ');
    expect(repo.asked, ['calm Tamil melodies']);
    expect(c.read(mixIntentProvider).result!.summary, 'Tamil · Melody · calm');
    final batch = c.read(shuffleQueueProvider).batches.single;
    expect(batch.source, 'candidates');
    expect([for (final s in batch.queue) s.title], ['C', 'B', 'A']); // only the fitting songs
  });

  test('nothing understood keeps the current picks and explains', () async {
    final c = _container(_IntentRepo(const IntentResponse(
      summary: '', candidates: [], count: 0, understood: false)));
    await c.read(mixIntentProvider.notifier).apply('asdf qwer');
    expect(c.read(mixIntentProvider).error, contains('language, genre, artist'));
    expect(c.read(shuffleQueueProvider).batches, isEmpty);
  });

  test('no fitting songs says so', () async {
    final c = _container(_IntentRepo(const IntentResponse(summary: 'Korean · sad', candidates: [], count: 0)));
    await c.read(mixIntentProvider.notifier).apply('sad korean');
    expect(c.read(mixIntentProvider).error, 'Nothing in your library fits “sad korean” yet.');
  });

  test('server errors surface their message', () async {
    final c = _container(_IntentRepo(const ShuffleNetworkError()));
    await c.read(mixIntentProvider.notifier).apply('calm tamil');
    expect(c.read(mixIntentProvider).error, contains('Cannot reach'));
  });

  test('a played mix stays on screen after its preview batches are cleared', () {
    Song s(String t) =>
        Song(id: t, title: t, artist: 'a', album: 'x', coverArt: '', duration: 100, track: 1, year: 2024);
    final described = (songs: [s('Sad 1'), s('Sad 2')], missing: 1);
    final normal = (songs: [s('Normal 1')], missing: 0);
    // A described mix is previewed: its batches win.
    expect(pickShownMix(hasPreview: true, fresh: described, pinned: null), described);
    // The user taps a song: playback clears the batches and the screen would fall back to the normal mix...
    expect(pickShownMix(hasPreview: false, fresh: normal, pinned: null), normal);
    // ...so the mix they played is pinned and keeps being listed (with its own missing count).
    expect(pickShownMix(hasPreview: false, fresh: normal, pinned: described), described);
    // New previews (reshuffle, a new description) override the pin.
    expect(pickShownMix(hasPreview: true, fresh: described, pinned: normal), described);
  });

  test('reset clears a described mix', () async {
    final c = _container(_IntentRepo(const IntentResponse(summary: 'x', candidates: ['A'], count: 1)));
    await c.read(mixIntentProvider.notifier).apply('anything');
    c.read(mixIntentProvider.notifier).reset();
    expect(c.read(mixIntentProvider).active, isFalse);
  });
}
