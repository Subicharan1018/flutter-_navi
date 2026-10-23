import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/composer.dart';
import 'library_provider.dart';

/// Every composer in the library, A–Z. Rebuilt only when the song mirror
/// changes (a sync), not on playback or any other state.
final composersProvider = Provider<AsyncValue<List<Composer>>>((ref) {
  return ref.watch(allSongsProvider).whenData(buildComposers);
});

/// One composer by [nameKey], or null if the library has none by that name.
final composerProvider = Provider.family<Composer?, String>((ref, key) {
  final all = ref.watch(composersProvider).asData?.value;
  if (all == null) return null;
  for (final c in all) {
    if (c.key == key) return c;
  }
  return null;
});

/// Composers matching a search query — the Search screen's Composers section.
final composerSearchProvider = Provider.autoDispose.family<List<Composer>, String>((ref, query) {
  final all = ref.watch(composersProvider).asData?.value;
  if (all == null) return const [];
  return matchComposers(all, query);
});
