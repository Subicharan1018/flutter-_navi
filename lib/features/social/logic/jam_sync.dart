import '../data/social_models.dart';

/// Pure sync rules for Jam, kept apart from the player so they can be tested
/// without audio.

/// How far a listener may drift from the host before being pulled back.
const int jamDriftToleranceMs = 1500;

/// Estimates `serverNow = deviceNow + offsetMs` from poll round trips, trusting
/// the fastest round trip seen recently (least asymmetric network delay).
class JamClock {
  int offsetMs = 0;
  int _bestRttMs = 1 << 30;
  int _samples = 0;

  /// [t0]/[t1]: device clock when the request left/returned; [serverMs]: the
  /// server's clock when it answered.
  void add(int t0, int t1, int serverMs) {
    if (serverMs <= 0) return;
    final rtt = t1 - t0;
    if (rtt < 0) return;
    // Let an old low-RTT sample go stale so a changed network path is learned.
    if (++_samples % 30 == 0) _bestRttMs = 1 << 30;
    if (rtt <= _bestRttMs) {
      _bestRttMs = rtt;
      offsetMs = serverMs - (t0 + rtt ~/ 2);
    }
  }

  int serverNow(int deviceNowMs) => deviceNowMs + offsetMs;
}

/// Where playback should be right now according to [s].
int projectPositionMs(JamState s, int serverNowMs) {
  if (!s.playing) return s.positionMs;
  final elapsed = serverNowMs - s.serverMs;
  return s.positionMs + (elapsed > 0 ? elapsed : 0);
}

enum QueueChange { none, append, removeOne, move, replace }

class QueueDiff {
  final QueueChange change;

  /// For [QueueChange.append]: how many of the existing items to keep.
  /// For [QueueChange.removeOne]: the index (in the applied queue) removed.
  /// For [QueueChange.move]: the index the item moved from.
  final int at;

  /// For [QueueChange.move]: the index it moved to.
  final int to;
  const QueueDiff(this.change, [this.at = 0, this.to = 0]);
}

/// How to turn the queue the player holds (by Jam item id) into [next] with
/// the least disruption: appends and single removals leave playback running.
QueueDiff diffQueue(List<int> applied, List<int> next, int currentIndex) {
  if (_same(applied, next)) return const QueueDiff(QueueChange.none);
  if (next.length > applied.length && _same(applied, next.sublist(0, applied.length))) {
    return QueueDiff(QueueChange.append, applied.length);
  }
  if (next.length == applied.length - 1) {
    for (var i = 0; i < applied.length; i++) {
      final without = [...applied]..removeAt(i);
      if (_same(without, next)) {
        // Removing the playing song needs a fresh start on its successor.
        return i == currentIndex ? const QueueDiff(QueueChange.replace) : QueueDiff(QueueChange.removeOne, i);
      }
    }
  }
  if (next.length == applied.length) {
    // One song dragged elsewhere: the player can reorder in place without
    // interrupting what is playing.
    for (var i = 0; i < applied.length; i++) {
      final j = next.indexOf(applied[i]);
      if (j < 0 || j == i) continue;
      final moved = [...applied]..removeAt(i);
      moved.insert(j, applied[i]);
      if (_same(moved, next)) return QueueDiff(QueueChange.move, i, j);
    }
  }
  return const QueueDiff(QueueChange.replace);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether a listener should seek to [targetMs]: only when really out of step.
bool needsDriftCorrection(int localMs, int targetMs) => (localMs - targetMs).abs() > jamDriftToleranceMs;

/// What the host's phone should tell the server, given what the player and the
/// server each believe. Null when they agree.
class HostPublish {
  final String action; // play | pause | jump | sync
  final int? index;
  final int? positionMs;
  const HostPublish(this.action, {this.index, this.positionMs});
}

HostPublish? hostPublish({
  required JamState server,
  required int serverNowMs,
  required int localIndex,
  required bool localPlaying,
  required int localPositionMs,
}) {
  if (localIndex != server.index) return HostPublish('jump', index: localIndex);
  if (localPlaying != server.playing) {
    return HostPublish(localPlaying ? 'play' : 'pause', positionMs: localPositionMs);
  }
  if (server.playing) {
    final target = projectPositionMs(server, serverNowMs);
    if ((localPositionMs - target).abs() > 600) {
      return HostPublish('sync', index: localIndex, positionMs: localPositionMs);
    }
  } else if ((localPositionMs - server.positionMs).abs() > 600) {
    return HostPublish('seek', positionMs: localPositionMs); // scrubbed while paused
  }
  return null;
}
