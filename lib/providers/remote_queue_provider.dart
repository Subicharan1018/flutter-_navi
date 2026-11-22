// =============================================================================
// Remote queue — the playing device's queue, seen and edited from another one
//
// While another of this account's devices plays (this one is the remote), its
// queue comes from the session server as song ids. This notifier turns them
// into songs for the queue pane and sends small queue edits (protocol 4) to
// the playing device. Each edit shows at once (optimistically) and is undone,
// with a message, if the server or the playing device refuses it.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../services/session_sync_service.dart';
import 'library_provider.dart' show songFromMetadata;
import 'player_provider.dart';
import 'session_sync_provider.dart';
import 'settings_provider.dart';

/// A queue as ids with the playing position: what the server keeps.
typedef IdQueue = ({List<String> ids, int index});

/// Where an insert lands: after the playing song, at the end, or at an index.
sealed class QueueSpot {
  const QueueSpot();
  static const next = _Next();
  static const end = _End();
  const factory QueueSpot.at(int index) = _At;
}

class _Next extends QueueSpot {
  const _Next();
}

class _End extends QueueSpot {
  const _End();
}

class _At extends QueueSpot {
  final int index;
  const _At(this.index);
}

/// Where [trackId] is in [ids]: at [hint] if it is still there, else its one
/// place. Null when it is gone or there twice (the server uses the same rule).
int? locateInQueue(List<String> ids, int? hint, String? trackId) {
  if (trackId == null) return null;
  if (hint != null && hint >= 0 && hint < ids.length && ids[hint] == trackId) return hint;
  int? found;
  for (var i = 0; i < ids.length; i++) {
    if (ids[i] != trackId) continue;
    if (found != null) return null;
    found = i;
  }
  return found;
}

/// The four queue edits as pure functions over an [IdQueue], mirroring what the
/// server does with them. An edit that no longer fits leaves the queue as is.
IdQueue applyQueueInsert(IdQueue q, List<String> trackIds, QueueSpot spot, {String? afterId}) {
  final ids = [...q.ids];
  var at = switch (spot) {
    _Next() => ids.isEmpty ? 0 : q.index + 1,
    _End() => ids.length,
    _At(:final index) => index,
  };
  if (spot is _At && afterId != null) {
    final above = locateInQueue(ids, at - 1, afterId);
    if (above != null) at = above + 1;
  }
  at = at.clamp(0, ids.length);
  final wasEmpty = ids.isEmpty;
  ids.insertAll(at, trackIds);
  return (ids: ids, index: !wasEmpty && at <= q.index ? q.index + trackIds.length : q.index);
}

IdQueue applyQueueRemove(IdQueue q, int index, String trackId) {
  final i = locateInQueue(q.ids, index, trackId);
  if (i == null || i == q.index) return q;
  final ids = [...q.ids]..removeAt(i);
  return (ids: ids, index: i < q.index ? q.index - 1 : q.index);
}

IdQueue applyQueueMove(IdQueue q, int from, int to, String trackId) {
  final i = locateInQueue(q.ids, from, trackId);
  if (i == null || q.ids.isEmpty) return q;
  final t = to.clamp(0, q.ids.length - 1);
  if (i == t) return q;
  final ids = [...q.ids];
  ids.insert(t, ids.removeAt(i));
  var cur = q.index;
  if (i == cur) {
    cur = t;
  } else if (i < cur && cur <= t) {
    cur--;
  } else if (t <= cur && cur < i) {
    cur++;
  }
  return (ids: ids, index: cur);
}

IdQueue applyQueueClearUpcoming(IdQueue q) =>
    q.index + 1 >= q.ids.length ? q : (ids: q.ids.sublist(0, q.index + 1), index: q.index);

/// Looks songs up by id: the library mirror first (no network), then the
/// server for the rest. Unknown ids are simply missing from the result.
typedef RemoteSongResolver = Future<List<Song>> Function(List<String> ids);

final remoteSongResolverProvider = Provider<RemoteSongResolver>((ref) {
  return (ids) async {
    final found = <Song>[];
    final missing = ids.toSet();
    try {
      final db = ref.read(appDatabaseProvider);
      final list = missing.toList();
      for (var i = 0; i < list.length; i += 500) {
        final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
        final rows = await (db.select(db.songMetadata)..where((t) => t.songId.isIn(chunk))).get();
        for (final r in rows) {
          found.add(songFromMetadata(r));
          missing.remove(r.songId);
        }
      }
    } catch (e) {
      debugPrint('[RemoteQueue] library lookup skipped: $e');
    }
    if (missing.isNotEmpty) {
      // Not in the mirror (a new song, or no library sync on this device): ask
      // the server, a bounded number at a time.
      final rest = missing.take(120).toList();
      found.addAll(await ref.read(subsonicServiceProvider).getSongs(rest));
    }
    return found;
  };
});

/// The playing device's queue as this remote shows it.
@immutable
class RemoteQueueState {
  /// The host's queue, with this device's not-yet-confirmed edits on top.
  final List<Song> songs;

  /// The playing song in [songs].
  final int index;

  /// Non-null while the host's queue can't be edited from here (`jam`).
  final String? locked;

  /// A message for the person (an edit was refused), and a counter so the
  /// same text twice still shows twice.
  final String? notice;
  final int noticeSeq;

  const RemoteQueueState({
    this.songs = const [],
    this.index = 0,
    this.locked,
    this.notice,
    this.noticeSeq = 0,
  });

  bool get editable => locked == null;
}

class _Pending {
  final String cmdId;
  final IdQueue Function(IdQueue) apply;
  final DateTime at;

  /// For an edit the server only forwards (a new queue): settled when the
  /// host's own report shows it, not when the server says "sent".
  final bool Function(PlaybackState)? confirmedBy;

  /// A refusal is explained elsewhere (the routed-play notice), not here.
  final bool quiet;
  _Pending(this.cmdId, this.apply, {this.confirmedBy, this.quiet = false}) : at = DateTime.now();
}

final remoteQueueProvider = NotifierProvider<RemoteQueueNotifier, RemoteQueueState>(RemoteQueueNotifier.new);

class RemoteQueueNotifier extends Notifier<RemoteQueueState> {
  /// An edit with no answer this long is forgotten: the server's queue wins.
  static const pendingTimeout = Duration(seconds: 10);

  PlaybackState _server = const PlaybackState.initial();
  final List<_Pending> _pending = [];
  final Map<String, Song> _songs = {};
  final Set<String> _resolving = {};
  String? _notice;
  int _noticeSeq = 0;

  SessionSyncService get _sync => ref.read(sessionSyncServiceProvider);

  @override
  RemoteQueueState build() {
    final svc = ref.watch(sessionSyncServiceProvider);
    final states = svc.stateStream.listen(_onServerState);
    final results = svc.resultStream.listen(_onResult);
    ref.onDispose(() {
      states.cancel();
      results.cancel();
    });
    _server = svc.currentState;
    _pending.clear();
    _resolveMissing(_server.queue);
    return _compose();
  }

  /// The ids as the person should see them now.
  IdQueue get view {
    var q = (ids: _server.queue, index: _server.queueIndex.clamp(0, _server.queue.isEmpty ? 0 : _server.queue.length - 1));
    for (final p in _pending) {
      q = p.apply(q);
    }
    return q;
  }

  RemoteQueueState _compose() {
    final q = view;
    return RemoteQueueState(
      songs: [for (final id in q.ids) _songs[id] ?? _placeholder(id)],
      index: q.index,
      locked: _server.queueLocked,
      notice: _notice,
      noticeSeq: _noticeSeq,
    );
  }

  static Song _placeholder(String id) => Song(
        id: id,
        title: 'Loading…',
        artist: '',
        album: '',
        coverArt: id,
        duration: 0,
        track: 0,
        year: 0,
      );

  void _onServerState(PlaybackState s) {
    _server = s;
    final now = DateTime.now();
    _pending.removeWhere((p) =>
        p.cmdId == s.causedByCmdId || now.difference(p.at) > pendingTimeout || (p.confirmedBy?.call(s) ?? false));
    _resolveMissing(s.queue);
    state = _compose();
  }

  void _onResult(CommandResult r) {
    final i = _pending.indexWhere((p) => p.cmdId == r.cmdId);
    if (i < 0) return;
    // Accepted: the confirming state (sent just before the answer) already
    // holds the edit. Refused: undo it on screen and say why.
    final p = _pending[i];
    if (r.ok && p.confirmedBy != null) return; // forwarded: the host's report settles it
    _pending.removeAt(i);
    if (!r.ok && !p.quiet) _say(r.message);
    state = _compose();
  }

  void _say(String message) {
    _notice = message;
    _noticeSeq++;
  }

  Future<void> _resolveMissing(List<String> ids) async {
    final missing = [for (final id in ids.toSet()) if (!_songs.containsKey(id) && !_resolving.contains(id)) id];
    if (missing.isEmpty) return;
    _resolving.addAll(missing);
    try {
      final found = await ref.read(remoteSongResolverProvider)(missing);
      for (final s in found) {
        _songs[s.id] = s;
      }
    } catch (e) {
      debugPrint('[RemoteQueue] could not look up queued songs: $e');
    } finally {
      _resolving.removeAll(missing);
    }
    if (ref.mounted) state = _compose();
  }

  /// Sends one edit and shows it at once. False when it couldn't be sent.
  bool _edit(QueueEditType type, Map<String, dynamic> args, IdQueue Function(IdQueue) apply) {
    if (!state.editable) {
      _say(const CommandResult(ok: false, action: 'queue', reason: 'queue_locked').message);
      state = _compose();
      return false;
    }
    final cmdId = _sync.sendQueueEdit(type, args);
    if (cmdId == null) {
      _say(const CommandResult(ok: false, action: 'queue', reason: 'offline').message);
      state = _compose();
      return false;
    }
    _pending.add(_Pending(cmdId, apply));
    state = _compose();
    return true;
  }

  /// Play next / Add to queue / a drop at [spot]. [songs] are remembered so
  /// they show with their names straight away.
  bool insert(List<Song> songs, QueueSpot spot) {
    if (songs.isEmpty) return false;
    for (final s in songs) {
      _songs[s.id] = s;
    }
    final ids = [for (final s in songs) s.id];
    final q = view;
    // A drop also names the song just above it, so the server can place it
    // even when the queue moved meanwhile ("after_id": null = the very top).
    String? afterId;
    var anchored = false;
    final Object position;
    switch (spot) {
      case _Next():
        position = 'next';
      case _End():
        position = 'end';
      case _At(:final index):
        position = index;
        anchored = index == 0 || index - 1 < q.ids.length;
        afterId = index > 0 && index - 1 < q.ids.length ? q.ids[index - 1] : null;
    }
    return _edit(
      QueueEditType.insert,
      {'track_ids': ids, 'position': position, if (anchored) 'after_id': afterId},
      (q) => applyQueueInsert(q, ids, spot, afterId: afterId),
    );
  }

  bool remove(int index) {
    final q = view;
    if (index < 0 || index >= q.ids.length || index == q.index) return false;
    final id = q.ids[index];
    return _edit(QueueEditType.remove, {'index': index, 'track_id': id}, (q) => applyQueueRemove(q, index, id));
  }

  bool move(int from, int to) {
    final q = view;
    if (from < 0 || from >= q.ids.length || to < 0 || to >= q.ids.length || from == to) return false;
    final id = q.ids[from];
    return _edit(QueueEditType.move, {'from': from, 'to': to, 'track_id': id}, (q) => applyQueueMove(q, from, to, id));
  }

  bool clearUpcoming() {
    final q = view;
    if (q.index + 1 >= q.ids.length) return false;
    return _edit(QueueEditType.clearUpcoming, const {}, applyQueueClearUpcoming);
  }

  /// A new queue for the playing device (a tap on a song or "Play" while this
  /// device is its remote), shown at once; [cmdId] is the command that carries it.
  void replace(List<Song> songs, int index, String cmdId) {
    for (final s in songs) {
      _songs[s.id] = s;
    }
    final ids = [for (final s in songs) s.id];
    final at = index.clamp(0, ids.isEmpty ? 0 : ids.length - 1);
    _pending.add(_Pending(
      cmdId,
      (_) => (ids: ids, index: at),
      confirmedBy: (s) => s.queue.length == ids.length && s.queueIndex == at && _sameIds(s.queue, ids),
      quiet: true,
    ));
    state = _compose();
  }

  static bool _sameIds(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Plays the song at [index] on the playing device.
  void jumpTo(int index) {
    final q = view;
    if (index < 0 || index >= q.ids.length) return;
    ref.read(playerProvider.notifier).remoteControl('play_track', index: index, trackId: q.ids[index]);
  }
}
