import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart';
import '../data/wrapped_models.dart';
import 'wrapped_loader.dart';

class _HiveWrappedStore implements WrappedStore {
  @override
  String? read(String key) => HiveBoxes.prefs.get(key) as String?;
  @override
  Future<void> write(String key, String value) => HiveBoxes.prefs.put(key, value);
}

/// Where a built Wrapped is kept (tests replace it).
final wrappedStoreProvider = Provider<WrappedStore>((ref) => _HiveWrappedStore());

/// The date Wrapped counts the current year from (tests replace it).
final wrappedNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The year's Wrapped, built on demand and kept on the device (one key per account and year).
final wrappedProvider = FutureProvider.autoDispose.family<WrappedData, int>((ref, year) {
  final repo = ref.watch(shuffleRepositoryProvider);
  final (server, user) = ref.watch(settingsProvider.select((s) => (s.serverUrl, s.username)));
  return loadWrapped(
    year: year,
    currentYear: ref.read(wrappedNowProvider)().year,
    storeKey: wrappedStoreKey(server, user, year),
    store: ref.read(wrappedStoreProvider),
    fetchYear: (y) => repo.getYearlyReplay(year: y),
    fetchMonth: (y, m) => repo.getMonthlyReplay(year: y, month: m),
  );
});
