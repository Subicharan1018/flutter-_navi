import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../../trending/logic/trending_providers.dart' show loadChartSongs;
import '../data/social_api.dart';
import '../data/social_models.dart';

final socialApiProvider = Provider<SocialApi>((ref) {
  return SocialApi(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'Social'));
});

bool _signedIn(Ref ref) {
  final (user, pass) = ref.watch(settingsProvider.select((s) => (s.username, s.password)));
  return user.isNotEmpty && pass.isNotEmpty;
}

/// This person's social choices. Off until they turn it on; changes save to
/// the server at once and the new value becomes the state.
class SocialSettingsNotifier extends AsyncNotifier<SocialSettings> {
  @override
  Future<SocialSettings> build() async {
    if (!_signedIn(ref)) return const SocialSettings();
    return ref.read(socialApiProvider).settings();
  }

  Future<void> save({bool? enabled, bool? hideActivity}) async {
    final saved = await ref.read(socialApiProvider).saveSettings(enabled: enabled, hideActivity: hideActivity);
    state = AsyncData(saved);
    // What other people can see of us, and what we can see, just changed.
    ref.invalidate(friendFeedProvider);
    ref.invalidate(socialUsersProvider);
    ref.invalidate(blendListProvider);
  }
}

final socialSettingsProvider =
    AsyncNotifierProvider<SocialSettingsNotifier, SocialSettings>(SocialSettingsNotifier.new);

/// Whether social features are on for this person (false while unknown).
final socialEnabledProvider = Provider<bool>(
  (ref) => ref.watch(socialSettingsProvider.select((s) => s.asData?.value.enabled ?? false)),
);

/// People who can be invited: the ones who also turned social features on.
final socialUsersProvider = FutureProvider.autoDispose<List<String>>(
  (ref) async {
    if (!_signedIn(ref) || !ref.watch(socialEnabledProvider)) return const [];
    return ref.read(socialApiProvider).users();
  },
  retry: (_, _) => null,
);

/// What friends are playing. Empty (and never requested) until this person
/// has turned social features on.
final friendFeedProvider = FutureProvider.autoDispose<FriendFeed>(
  (ref) async {
    if (!_signedIn(ref) || !ref.watch(socialEnabledProvider)) return const FriendFeed();
    return ref.read(socialApiProvider).activity();
  },
  retry: (_, _) => null,
);

final collabListProvider = FutureProvider.autoDispose<List<CollabPlaylist>>(
  (ref) async {
    if (!_signedIn(ref)) return const [];
    return ref.read(socialApiProvider).collabList();
  },
  retry: (_, _) => null,
);

final collabDetailProvider = FutureProvider.autoDispose.family<CollabPlaylist, String>(
  (ref, id) => ref.read(socialApiProvider).collabGet(id),
  retry: (_, _) => null,
);

/// Library songs for a comma-joined list of ids (shared playlists, Blends),
/// from the local mirror first and the server for the rest.
final socialSongsProvider = FutureProvider.autoDispose.family<Map<String, Song>, String>((ref, joinedIds) async {
  if (joinedIds.isEmpty) return const {};
  return loadChartSongs(ref, joinedIds.split(','));
});

final blendListProvider = FutureProvider.autoDispose<List<Blend>>(
  (ref) async {
    if (!_signedIn(ref) || !ref.watch(socialEnabledProvider)) return const [];
    return ref.read(socialApiProvider).blends();
  },
  retry: (_, _) => null,
);

final blendDetailProvider = FutureProvider.autoDispose.family<Blend, String>(
  (ref, id) => ref.read(socialApiProvider).blend(id),
  retry: (_, _) => null,
);
