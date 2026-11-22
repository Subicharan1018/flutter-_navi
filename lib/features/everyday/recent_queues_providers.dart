import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import '../../models/song.dart';
import '../../player/queue_snapshot.dart' show SavedQueue;
import '../../providers/settings_provider.dart';
import 'recent_queues.dart';

/// Where the list is kept: one json string in the session box.
abstract class RecentQueuesBackend {
  String? read();
  Future<void> write(String value);
}

class HiveRecentQueuesBackend implements RecentQueuesBackend {
  static const key = 'recentQueues_v1';

  @override
  String? read() {
    final v = HiveBoxes.session.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String value) => HiveBoxes.session.put(key, value);
}

final recentQueuesBackendProvider = Provider<RecentQueuesBackend>((ref) => HiveRecentQueuesBackend());

/// `server|username` of whoever is signed in.
final recentQueuesAccountProvider = Provider<String>((ref) {
  final (server, user) = ref.watch(settingsProvider.select((s) => (s.serverUrl, s.username)));
  return SavedQueue.accountKey(server, user);
});

/// This account's remembered queues, newest first.
class RecentQueuesNotifier extends Notifier<List<RecentQueue>> {
  String get _account => ref.read(recentQueuesAccountProvider);

  List<RecentQueue> _all = const [];

  @override
  List<RecentQueue> build() {
    try {
      _all = RecentQueues.decode(ref.read(recentQueuesBackendProvider).read());
    } catch (_) {
      _all = const []; // storage not open (a test, a first frame)
    }
    return RecentQueues.forAccount(_all, _account);
  }

  /// Remembers [songs] as the queue that is being replaced. Never throws:
  /// bookkeeping must not break playback.
  void remember(List<Song> songs, {String? source, int index = 0, DateTime? now}) {
    try {
      _all = RecentQueues.remember(
        _all,
        RecentQueue(
          account: _account,
          savedAt: now ?? DateTime.now(),
          songs: List.of(songs),
          source: source,
          index: index,
        ),
      );
      state = RecentQueues.forAccount(_all, _account);
      ref.read(recentQueuesBackendProvider).write(RecentQueues.encode(_all));
    } catch (_) {}
  }

  void forget(RecentQueue q) {
    _all = [
      for (final x in _all)
        if (!identical(x, q)) x,
    ];
    state = RecentQueues.forAccount(_all, _account);
    ref.read(recentQueuesBackendProvider).write(RecentQueues.encode(_all));
  }
}

final recentQueuesProvider = NotifierProvider<RecentQueuesNotifier, List<RecentQueue>>(RecentQueuesNotifier.new);
