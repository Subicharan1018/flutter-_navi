import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../ai_shuffle/data/models/feedback_request.dart';

/// One play that still has something to tell a server.
///
/// A play has up to two legs: the Navidrome scrobble (history, "recently
/// played") and the Smart Shuffle `/feedback` post (Flow, Replay, stats). Each
/// leg is marked sent only after the server answered 2xx; the row goes away
/// when no leg is left.
class OutboxRow {
  final String playId;
  final String songId;

  /// When the play started (epoch ms): what both servers are told, however
  /// late the delivery.
  final int startedAtMs;
  final bool scrobblePending;
  final FeedbackRequest? feedback;
  final bool feedbackPending;
  final int attempts;

  const OutboxRow({
    required this.playId,
    required this.songId,
    required this.startedAtMs,
    this.scrobblePending = false,
    this.feedback,
    this.feedbackPending = false,
    this.attempts = 0,
  });

  bool get done => !scrobblePending && !feedbackPending;

  OutboxRow copyWith({
    bool? scrobblePending,
    FeedbackRequest? feedback,
    bool? feedbackPending,
    int? attempts,
    String? songId,
  }) =>
      OutboxRow(
        playId: playId,
        songId: songId ?? this.songId,
        startedAtMs: startedAtMs,
        scrobblePending: scrobblePending ?? this.scrobblePending,
        feedback: feedback ?? this.feedback,
        feedbackPending: feedbackPending ?? this.feedbackPending,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toJson() => {
        'play_id': playId,
        'song_id': songId,
        'ts': startedAtMs,
        'scrobble': scrobblePending,
        'feedback_pending': feedbackPending,
        if (feedback != null) 'feedback': feedback!.toJson(),
        'attempts': attempts,
      };

  static OutboxRow? tryParse(Object? raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      final fb = j['feedback'];
      return OutboxRow(
        playId: j['play_id'] as String,
        songId: j['song_id'] as String,
        startedAtMs: (j['ts'] as num).toInt(),
        scrobblePending: j['scrobble'] == true,
        feedbackPending: j['feedback_pending'] == true,
        feedback: fb is Map ? FeedbackRequest.fromJson(Map<String, dynamic>.from(fb)) : null,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Device-side queue of plays not yet delivered, kept in a Hive box so it
/// survives restarts and every write is a single atomic put. Nothing here
/// touches the network; [PlayOutboxDelivery] does that.
///
/// Rows are keyed by play id, so recording the same play twice (a retry, or
/// the scrobble and feedback legs of one play) merges instead of duplicating.
class PlayOutbox {
  PlayOutbox(this._box, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final Box _box;
  final DateTime Function() _now;

  static const maxRows = 5000;
  static const maxAge = Duration(days: 90);

  /// Rows waiting, oldest play first.
  List<OutboxRow> pending() {
    final rows = <OutboxRow>[];
    for (final v in _box.values) {
      final r = OutboxRow.tryParse(v);
      if (r != null && !r.done) rows.add(r);
    }
    rows.sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
    return rows;
  }

  /// Plays with something still to deliver.
  int get pendingCount => pending().length;

  OutboxRow? row(String playId) {
    final v = _box.get(playId);
    return v == null ? null : OutboxRow.tryParse(v);
  }

  Future<void> _put(OutboxRow r) => _box.put(r.playId, jsonEncode(r.toJson()));

  /// The play passed the scrobble threshold. Songs that never reach Navidrome
  /// (device files) pass [scrobble] false and are not queued for it.
  Future<void> recordScrobble({
    required String playId,
    required String songId,
    required int startedAtMs,
    bool scrobble = true,
  }) async {
    if (!scrobble) return;
    final old = row(playId);
    await _put((old ?? OutboxRow(playId: playId, songId: songId, startedAtMs: startedAtMs))
        .copyWith(scrobblePending: true));
    await _pruneSometimes();
  }

  /// The play ended or was skipped; [request] was built at that moment and is
  /// sent as it is, however late.
  Future<void> recordFeedback({
    required String playId,
    required String songId,
    required int startedAtMs,
    required FeedbackRequest request,
  }) async {
    final old = row(playId);
    // Already queued: a second report of one play adds nothing.
    if (old != null && old.feedback != null) return;
    final stamped = request.withPlay(playId: playId, playedAtMs: startedAtMs);
    await _put((old ?? OutboxRow(playId: playId, songId: songId, startedAtMs: startedAtMs))
        .copyWith(feedback: stamped, feedbackPending: true));
    await _pruneSometimes();
  }

  /// A leg was delivered (2xx). The row is removed once nothing is left.
  Future<void> markSent(String playId, {bool scrobble = false, bool feedback = false}) async {
    final r = row(playId);
    if (r == null) return;
    final next = r.copyWith(
      scrobblePending: scrobble ? false : r.scrobblePending,
      feedbackPending: feedback ? false : r.feedbackPending,
    );
    if (next.done) {
      await _box.delete(playId);
    } else {
      await _put(next);
    }
  }

  Future<void> markAttempt(String playId) async {
    final r = row(playId);
    if (r != null) await _put(r.copyWith(attempts: r.attempts + 1));
  }

  /// Gives up on one row (the server refused it for good).
  Future<void> drop(String playId) => _box.delete(playId);

  /// Follows a server upgrade that renamed song ids.
  Future<void> remapSongIds(Map<String, String> idMap) async {
    for (final r in pending()) {
      final next = idMap[r.songId];
      if (next == null) continue;
      final fb = r.feedback;
      await _put(r.copyWith(
        songId: next,
        feedback: fb == null || fb.filePath != r.songId
            ? fb
            : FeedbackRequest.fromJson({...fb.toJson(), 'file_path': next}),
      ));
    }
  }

  /// [prune] parses every row, so it runs when the box is at its cap and
  /// otherwise once per 50 rows.
  Future<void> _pruneSometimes() async {
    if (_box.length >= maxRows || _box.length % 50 == 0) await prune();
  }

  /// Keeps at most [maxRows] rows no older than [maxAge]. Over the cap, the
  /// oldest plays lose their Navidrome scrobble first (it only feeds history),
  /// then the oldest rows go.
  Future<void> prune() async {
    final cutoff = _now().subtract(maxAge).millisecondsSinceEpoch;
    for (final k in _box.keys.toList()) {
      final r = OutboxRow.tryParse(_box.get(k));
      if (r == null || r.done || r.startedAtMs < cutoff) await _box.delete(k);
    }
    var over = _box.length - maxRows;
    if (over <= 0) return;
    final rows = pending();
    for (final r in rows) {
      if (over <= 0) break;
      if (r.scrobblePending && r.feedbackPending) {
        await _put(r.copyWith(scrobblePending: false));
      } else if (r.scrobblePending) {
        await _box.delete(r.playId);
        over--;
      }
    }
    for (final r in pending()) {
      if (over <= 0) break;
      await _box.delete(r.playId);
      over--;
    }
  }
}
