import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai_shuffle/data/models/feedback_request.dart';
import 'play_outbox.dart';

/// Sends one Navidrome scrobble dated [timeMs]. Throws unless the server
/// answered 2xx.
typedef ScrobbleSender = Future<void> Function(String songId, int timeMs);

/// Sends one `/feedback` post. Throws unless the server answered 2xx.
typedef FeedbackSender = Future<void> Function(FeedbackRequest request);

/// The server refused this play for good (a 4xx that a retry cannot fix): the
/// leg is dropped instead of retried forever.
class OutboxRefused implements Exception {
  final String reason;
  const OutboxRefused(this.reason);
  @override
  String toString() => 'refused: $reason';
}

/// Delivers [PlayOutbox] rows: oldest first, one at a time, paced under the
/// shuffle server's 60/min feedback limit. A failure stops the batch (the
/// network or server is down) and a retry is scheduled with growing delays;
/// a leg that keeps failing is dropped after [maxAttempts] tries.
class PlayOutboxDelivery {
  PlayOutboxDelivery({
    required this.outbox,
    required this.sendScrobble,
    required this.sendFeedback,
    this.canSend = _always,
    this.pace = const Duration(milliseconds: 1200),
    this.maxAttempts = 30,
    this.firstRetry = const Duration(seconds: 30),
    this.maxRetry = const Duration(minutes: 15),
    this.onChanged,
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future.delayed;

  static bool _always() => true;

  final PlayOutbox outbox;
  final ScrobbleSender sendScrobble;
  final FeedbackSender sendFeedback;

  /// False while signed out or without a network: nothing is attempted and no
  /// attempt is counted against the rows.
  final bool Function() canSend;
  final Duration pace;
  final int maxAttempts;
  final Duration firstRetry;
  final Duration maxRetry;

  /// Called after the pending count may have changed.
  final VoidCallback? onChanged;
  final Future<void> Function(Duration) _wait;

  bool _running = false;
  bool _again = false;
  bool _disposed = false;
  int _failures = 0;
  Timer? _retry;

  /// Sends everything waiting. Calls made while a flush runs fold into it.
  Future<void> flush() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _flushOnce();
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
    _scheduleRetryIfNeeded();
  }

  Future<void> _flushOnce() async {
    for (final row in outbox.pending()) {
      if (_disposed || !canSend()) return;
      final ok = await _deliver(row);
      onChanged?.call();
      if (!ok) {
        _failures++;
        return;
      }
      _failures = 0;
    }
  }

  /// Both legs of [row], each tried even if the other fails. False when a leg
  /// failed and should be retried later.
  Future<bool> _deliver(OutboxRow row) async {
    var allSent = true;
    var sentFeedback = false;
    if (row.scrobblePending) {
      if (await _attempt(() => sendScrobble(row.songId, row.startedAtMs), row) == _Leg.sent) {
        await outbox.markSent(row.playId, scrobble: true);
      } else {
        allSent = false;
      }
    }
    final fb = row.feedback;
    if (row.feedbackPending) {
      if (fb == null) {
        // Nothing to send for this leg; do not wait for it.
        await outbox.markSent(row.playId, feedback: true);
      } else if (await _attempt(() => sendFeedback(fb), row) == _Leg.sent) {
        await outbox.markSent(row.playId, feedback: true);
        sentFeedback = true;
      } else {
        allSent = false;
      }
    }
    if (sentFeedback && pace > Duration.zero) await _wait(pace);
    return allSent;
  }

  Future<_Leg> _attempt(Future<void> Function() send, OutboxRow row) async {
    try {
      await send();
      return _Leg.sent;
    } on OutboxRefused catch (e) {
      debugPrint('[PlayOutbox] ${row.playId} dropped: $e');
      return _Leg.sent; // counted as done: it can never succeed
    } catch (e) {
      await outbox.markAttempt(row.playId);
      if (row.attempts + 1 >= maxAttempts) {
        debugPrint('[PlayOutbox] ${row.playId} dropped after ${row.attempts + 1} tries: $e');
        return _Leg.sent;
      }
      debugPrint('[PlayOutbox] ${row.playId} will retry: $e');
      return _Leg.retry;
    }
  }

  void _scheduleRetryIfNeeded() {
    _retry?.cancel();
    if (_disposed || _failures == 0 || outbox.pendingCount == 0) return;
    final ms = firstRetry.inMilliseconds * (1 << (_failures - 1).clamp(0, 10));
    final delay = Duration(milliseconds: ms.clamp(0, maxRetry.inMilliseconds));
    _retry = Timer(delay, () => unawaited(flush()));
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
  }
}

enum _Leg { sent, retry }
