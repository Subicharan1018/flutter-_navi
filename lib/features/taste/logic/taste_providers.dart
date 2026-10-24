import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../discover/logic/discover_providers.dart' show discoverProvider;
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import '../../weekly_mix/logic/weekly_mix_providers.dart' show weeklyMixProvider;

/// The first name in "A, B & C": a collaboration is not one artist.
String firstName(String raw) {
  for (final part in raw.split(RegExp(r'[;,•&/]'))) {
    if (part.trim().isNotEmpty) return part.trim();
  }
  return '';
}

/// What "Never recommend" can offer for [song]: the song itself, and its first
/// artist and first composer when it has them (a composer equal to the artist
/// is offered once).
List<TasteExclusion> neverOptionsFor(Song song) {
  final artist = firstName(song.artist);
  final composer = firstName(song.composer);
  return [
    TasteExclusion(kind: TasteKind.song, value: song.id, label: song.title),
    if (artist.isNotEmpty) TasteExclusion(kind: TasteKind.artist, value: artist, label: artist),
    if (composer.isNotEmpty && composer.toLowerCase() != artist.toLowerCase())
      TasteExclusion(kind: TasteKind.composer, value: composer, label: composer),
  ];
}

/// Everything the listener told the server never to recommend. Kept alive: the
/// song sheet adds to it and closes before the request ends.
final tasteExclusionsProvider = AsyncNotifierProvider<TasteExclusions, List<TasteExclusion>>(TasteExclusions.new);

class TasteExclusions extends AsyncNotifier<List<TasteExclusion>> {
  @override
  Future<List<TasteExclusion>> build() async {
    if (!watchSignedIn(ref)) return const [];
    return ref.read(listenApiProvider).exclusions();
  }

  Future<void> add(TasteExclusion e) => _change(() => ref.read(listenApiProvider).addExclusion(e.kind, e.value, label: e.label));

  Future<void> remove(TasteExclusion e) => _change(() => ref.read(listenApiProvider).removeExclusion(e.kind, e.value));

  /// Runs [call], keeps the list it returns, and refreshes what the change affects.
  Future<void> _change(Future<List<TasteExclusion>> Function() call) async {
    final list = await call();
    if (!ref.mounted) return;
    state = AsyncData(list);
    ref.invalidate(weeklyMixProvider);
    ref.invalidate(discoverProvider);
  }
}
