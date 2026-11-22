import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import 'song_trim.dart';

/// Where trims are kept: one json string in the prefs box.
abstract class SongTrimBackend {
  String? read();
  Future<void> write(String value);
}

class HiveSongTrimBackend implements SongTrimBackend {
  static const key = 'songTrims_v1';

  @override
  String? read() {
    final v = HiveBoxes.prefs.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String value) => HiveBoxes.prefs.put(key, value);
}

final songTrimBackendProvider = Provider<SongTrimBackend>((ref) => HiveSongTrimBackend());

class SongTrimsNotifier extends Notifier<SongTrims> {
  @override
  SongTrims build() {
    try {
      return SongTrims.decode(ref.read(songTrimBackendProvider).read());
    } catch (_) {
      return const SongTrims(); // no storage (a test, a first frame): no trims
    }
  }

  /// Saves [trim] for [songId] (normalised to [durationSec]); a trim with
  /// neither point removes the entry.
  Future<void> set(String songId, SongTrim trim, {required int durationSec}) async {
    state = state.with_(songId, trim.normalized(durationSec * 1000));
    await ref.read(songTrimBackendProvider).write(state.encode());
  }

  Future<void> clear(String songId) async {
    state = state.with_(songId, SongTrim.none);
    await ref.read(songTrimBackendProvider).write(state.encode());
  }
}

final songTrimsProvider = NotifierProvider<SongTrimsNotifier, SongTrims>(SongTrimsNotifier.new);
