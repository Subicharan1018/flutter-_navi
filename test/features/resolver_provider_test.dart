import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/logic/recommendation_resolver.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';

Song _song(String id, String title) => Song(
      id: id,
      title: title,
      artist: 'A',
      album: 'Al',
      coverArt: 'c$id',
      duration: 100,
      track: 1,
      year: 2025,
    );

void main() {
  test('the resolver is built once per library, not once per read (Shuffle tab build cost)', () async {
    final container = ProviderContainer(
      overrides: [allSongsProvider.overrideWith((ref) async => [_song('1', 'One'), _song('2', 'Two')])],
    );
    addTearDown(container.dispose);
    await container.read(allSongsProvider.future);

    final first = container.read(recommendationResolverProvider);
    final second = container.read(recommendationResolverProvider);
    expect(identical(first, second), isTrue);
    expect(first.match('two', 'a')?.id, '2');
  });
}
