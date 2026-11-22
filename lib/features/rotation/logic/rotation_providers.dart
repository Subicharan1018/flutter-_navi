import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../../discover/logic/discover_providers.dart' show discoverProvider;
import '../../listen/data/listen_models.dart';
import '../../listen/logic/listen_providers.dart';
import '../../weekly_mix/logic/weekly_mix_providers.dart' show weeklyMixProvider;
import '../data/rotation_api.dart';
import '../data/rotation_models.dart';

final rotationApiProvider = Provider<RotationApi>((ref) {
  return RotationApi(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'Rotation'));
});

/// Songs resting, songs that belong to a season, and the settings for both.
/// Kept alive: the song menu changes it and closes before the request ends.
final rotationProvider = AsyncNotifierProvider<RotationNotifier, Rotation>(RotationNotifier.new);

class RotationNotifier extends AsyncNotifier<Rotation> {
  @override
  Future<Rotation> build() async {
    if (!watchSignedIn(ref)) return const Rotation();
    return ref.read(rotationApiProvider).rotation();
  }

  RotationApi get _api => ref.read(rotationApiProvider);

  /// Rests [song] for [length]; the server leaves it out of mixes until then.
  Future<void> rest(Song song, RestLength length) async {
    await _api.rest(song.id, length.days, label: song.title);
    await _changed();
  }

  Future<void> unrest(String songId) async {
    await _api.unrest(songId);
    await _changed();
  }

  /// [season] is a season key, `none` (never seasonal) or null (forget the tag).
  Future<void> setSeason(String songId, String? season) async {
    await _api.setSeason(songId, season);
    await _changed();
  }

  Future<void> savePrefs({bool? autoRest, bool? seasons, bool? back}) async {
    final prefs = await _api.savePrefs(autoRest: autoRest, seasons: seasons, back: back);
    final now = state.asData?.value ?? const Rotation();
    if (!ref.mounted) return;
    state = AsyncData(Rotation(resting: now.resting, seasonal: now.seasonal, seasons: now.seasons, prefs: prefs));
    await _changed();
  }

  /// Re-reads the lists and refreshes what the change affects.
  Future<void> _changed() async {
    final fresh = await _api.rotation();
    if (!ref.mounted) return;
    state = AsyncData(fresh);
    ref.invalidate(weeklyMixProvider);
    ref.invalidate(discoverProvider);
    ref.invalidate(backInRotationProvider);
  }
}

/// Home's "Back in rotation" shelf: loved long ago, quiet for two months. The
/// server picks a different set each day. Empty when there is none or the
/// listener turned it off.
final backInRotationProvider = FutureProvider.autoDispose<List<ListenPick>>(
  (ref) async {
    if (!watchSignedIn(ref)) return const [];
    return ref.read(rotationApiProvider).back();
  },
  retry: (_, _) => null,
);

/// A few "back in rotation" songs spread through [picks], the way Smart
/// Shuffle's queue is built: at most [max], one slot in about [every], none in
/// the first [lead] places (the next song is the recommender's own pick).
/// Songs already in [picks] are not added twice. Pure, so it can be tested.
List<Song> blendBackInRotation(
  List<Song> picks,
  List<Song> back, {
  int every = 6,
  int max = 3,
  int lead = 2,
  Random? random,
}) {
  if (picks.isEmpty || back.isEmpty) return picks;
  final rng = random ?? Random();
  final have = {for (final s in picks) s.id};
  final fresh = [for (final s in back) if (have.add(s.id)) s]..shuffle(rng);
  final out = [...picks];
  final room = (picks.length ~/ every).clamp(0, max);
  var added = 0;
  for (final s in fresh) {
    if (added >= room) break;
    // 0-based slot in the final list: lead + added*every, nudged by luck inside the gap.
    final slot = lead + added * every + rng.nextInt(every - 1);
    out.insert(slot.clamp(0, out.length), s);
    added++;
  }
  return out;
}

/// Smart Shuffle's hook: loads the listener's back-in-rotation songs and
/// blends them into [picks], only with songs from [candidates] (the list being
/// shuffled). Any failure leaves [picks] as they were.
final backBiasProvider = Provider<BackBias>(BackBias.new);

class BackBias {
  final Ref _ref;
  BackBias(this._ref);

  Future<List<Song>> blend(List<Song> picks, Map<String, Song> candidates, {Random? random}) async {
    try {
      if (!_ref.read(settingsProvider.select((s) => s.username.isNotEmpty && s.password.isNotEmpty))) return picks;
      final back = await _ref.read(rotationApiProvider).back(limit: 40);
      final songs = [for (final p in back) ?candidates[p.songId]];
      return blendBackInRotation(picks, songs, random: random);
    } catch (_) {
      return picks;
    }
  }
}
