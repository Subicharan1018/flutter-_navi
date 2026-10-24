import '../../listen/data/listen_models.dart';

/// What one Flow run remembers, and the rules for when to ask for more. Pure
/// Dart: [FlowController] feeds it what the player does.
class FlowSession {
  /// A song heard less than this is a skip; at least [playedRatio] is a play.
  static const double skipRatio = 0.3;
  static const double playedRatio = 0.8;

  /// Ask for another batch when this many songs or fewer are left up next.
  static const int refillAt = 3;
  static const int batchSize = 8;
  static const int firstBatchSize = 10;

  /// After this many failures in a row Flow stops and says so.
  static const int maxFailures = 4;
  static const int maxSeen = 500;
  static const int maxFeedback = 80;

  final List<String> _seen = [];
  final Set<String> _seenSet = {};
  final List<FlowFeedback> _feedback = [];

  int _failures = 0;
  DateTime? _retryAt;
  bool fetching = false;

  /// Every song Flow has put in the queue, oldest first (the server skips them).
  List<String> get seen => List.unmodifiable(_seen);

  /// What you did with the songs so far, oldest first.
  List<FlowFeedback> get feedback => List.unmodifiable(_feedback);

  int get failures => _failures;
  bool get exhausted => _failures >= maxFailures;

  void served(Iterable<String> ids) {
    for (final id in ids) {
      if (_seenSet.add(id)) _seen.add(id);
    }
    while (_seen.length > maxSeen) {
      _seenSet.remove(_seen.removeAt(0));
    }
  }

  bool wasServed(String id) => _seenSet.contains(id);

  void _note(FlowFeedback f) {
    if (!_seenSet.contains(f.songId) || _feedback.contains(f)) return;
    _feedback.add(f);
    if (_feedback.length > maxFeedback) _feedback.removeAt(0);
  }

  /// The song [prevId] ended (or was left) after being heard for [heard] of
  /// its [durationSec]: a skip, a play, or neither (somewhere in between).
  void left(String prevId, {required Duration heard, required int durationSec}) {
    if (durationSec <= 0) return;
    final ratio = heard.inMilliseconds / (durationSec * 1000);
    if (ratio < skipRatio) {
      _note(FlowFeedback(prevId, FlowAction.skip));
    } else if (ratio >= playedRatio) {
      _note(FlowFeedback(prevId, FlowAction.play));
    }
  }

  /// Songs that just got starred count as likes, when Flow played them.
  void starredChanged(Set<String> before, Set<String> after) {
    for (final id in after.difference(before)) {
      _note(FlowFeedback(id, FlowAction.like));
    }
  }

  /// Whether to ask the server for more now. [upNext] is how many songs are queued after the current one.
  bool wantsMore(int upNext, {DateTime? now}) {
    if (fetching || exhausted || upNext > refillAt) return false;
    final retry = _retryAt;
    return retry == null || !(now ?? DateTime.now()).isBefore(retry);
  }

  void succeeded() {
    _failures = 0;
    _retryAt = null;
  }

  void failed({DateTime? now, Duration backoff = const Duration(seconds: 20)}) {
    _failures++;
    _retryAt = (now ?? DateTime.now()).add(backoff);
  }
}
