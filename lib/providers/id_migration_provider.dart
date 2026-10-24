import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import '../features/ai_shuffle/logic/shuffle_providers.dart';
import 'download_provider.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

/// A Navidrome upgrade can give songs new ids (0.58 → 0.64 changed 901 of
/// 1,036). The server remaps its own stores and publishes the map at
/// GET /id-map; this applies it to everything on the device that remembers
/// song ids — play history, weights, pairs, the library mirror, downloaded
/// files and their records, cached BPMs — once per map `epoch`.
///
/// Order matters: the local database is rewritten in one transaction and the
/// epoch recorded right after, because a map with swaps (one song's old id is
/// another's new id) must never be applied twice. Downloads and BPM keys
/// follow; a failure there costs a re-download, never history.
class IdMigration {
  static const kEpoch = 'nd_id_map_epoch';
  static const timeout = Duration(seconds: 8);

  final Ref ref;
  IdMigration(this.ref);

  /// Returns how many ids were remapped (0 when there was nothing to do).
  Future<int> runIfNeeded() async {
    final String? epoch;
    final Map<String, String> map;
    try {
      (epoch, map) = await ref.read(shuffleRepositoryProvider).getIdMap().timeout(timeout);
    } catch (e) {
      debugPrint('[IdMigration] map unavailable, retry next start: $e');
      return 0;
    }
    if (epoch == null || HiveBoxes.prefs.get(kEpoch) == epoch) return 0;
    if (map.isEmpty) {
      await HiveBoxes.prefs.put(kEpoch, epoch);
      return 0;
    }

    await ref.read(appDatabaseProvider).remapSongIds(map);
    await HiveBoxes.prefs.put(kEpoch, epoch);       // DB done: never apply this map again

    try {
      final moved = await ref.read(offlineServiceProvider).remapSongIds(map);
      debugPrint('[IdMigration] $moved downloaded songs moved to new ids');
    } catch (e) {
      debugPrint('[IdMigration] downloads not remapped: $e');
    }
    await _remapBpmKeys(map);
    // Rebuild the library from the server now, pruning anything still stale.
    await resetLibrarySyncClock();
    ref.invalidate(allSongsProvider);
    debugPrint('[IdMigration] epoch $epoch applied (${map.length} ids)');
    return map.length;
  }

  Future<void> _remapBpmKeys(Map<String, String> map) async {
    try {
      final box = HiveBoxes.audio;
      final moves = <String, dynamic>{};
      for (final e in map.entries) {
        final v = box.get('bpm_${e.key}');
        if (v != null) moves['bpm_${e.value}'] = v;
      }
      await box.deleteAll([for (final old in map.keys) 'bpm_$old']);
      await box.putAll(moves);
    } catch (e) {
      debugPrint('[IdMigration] BPM cache not remapped: $e');   // recomputed on demand
    }
  }
}

final idMigrationProvider = Provider<IdMigration>(IdMigration.new);
