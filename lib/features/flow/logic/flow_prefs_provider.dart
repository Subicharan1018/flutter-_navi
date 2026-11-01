import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../listen/data/listen_api.dart';
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import '../../weekly_mix/logic/weekly_mix_providers.dart' show weeklyMixProvider;

/// The Flow language setting, kept on the server so phone, TV and desktop share
/// it. Kept alive: Settings changes it and the screen can close before the
/// request ends.
final flowPrefsProvider = AsyncNotifierProvider<FlowPrefsNotifier, FlowPrefs>(FlowPrefsNotifier.new);

class FlowPrefsNotifier extends AsyncNotifier<FlowPrefs> {
  @override
  Future<FlowPrefs> build() async {
    if (!watchSignedIn(ref)) return const FlowPrefs();
    return ref.read(listenApiProvider).flowPrefs();
  }

  /// Picks the languages Flow and the weekly mix draw from; an empty list is "Any".
  Future<void> setLanguages(List<String> codes) => _save(languages: codes);

  /// "Try new languages".
  Future<void> setExplore(bool on) => _save(explore: on);

  /// Shows the change at once, saves it, and puts the previous setting back if the
  /// server says no. A saved change rebuilds the weekly mix, which follows it.
  Future<void> _save({List<String>? languages, bool? explore}) async {
    final before = state.asData?.value;
    if (before == null) throw const ListenException('Your settings haven’t loaded yet. Try again in a moment.');
    state = AsyncData(before.copyWith(languages: languages, explore: explore));
    try {
      final saved = await ref.read(listenApiProvider).saveFlowPrefs(languages: languages, explore: explore);
      if (!ref.mounted) return;
      state = AsyncData(saved);
      ref.invalidate(weeklyMixProvider);
    } catch (_) {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }
}
