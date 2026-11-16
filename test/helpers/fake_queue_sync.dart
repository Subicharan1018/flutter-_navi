import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/session_sync_service.dart';

/// Just enough of the session link for a remote's queue: the host's state comes
/// in, queue edits go out (recorded), and the server's answers come back.
class FakeQueueSync extends Fake implements SessionSyncService {
  final _states = StreamController<PlaybackState>.broadcast(sync: true);
  final _results = StreamController<CommandResult>.broadcast(sync: true);
  PlaybackState _current;

  /// Every edit sent: (type, args, cmdId).
  final sent = <(QueueEditType, Map<String, dynamic>, String)>[];

  /// Plain commands (play_track, next…): (action, index, trackId).
  final commands = <(String, int?, String?)>[];

  /// False: the link is down, nothing can be sent.
  bool online = true;

  FakeQueueSync(this._current);

  @override
  PlaybackState get currentState => _current;
  @override
  Stream<PlaybackState> get stateStream => _states.stream;
  @override
  Stream<CommandResult> get resultStream => _results.stream;
  @override
  Stream<RemoteCommand> get commandStream => const Stream.empty();
  @override
  Stream<PrepareTransfer> get prepareStream => const Stream.empty();

  @override
  String? sendQueueEdit(QueueEditType type, Map<String, dynamic> args) {
    if (!online) return null;
    final id = 'cmd-${sent.length + 1}';
    sent.add((type, args, id));
    return id;
  }

  @override
  void sendCommand(String action, {int? positionMs, double? volume, String? trackId, int? index, List<String>? queue, String? target}) {
    commands.add((action, index, trackId));
  }

  /// The server's state (as the host reported it, or after an edit).
  void hostState(List<String> queue, int index, {String? causedBy, String? locked, int version = 1}) {
    _current = PlaybackState(
      activeDevice: 'host',
      activeDeviceName: 'Living room PC',
      trackId: queue.isEmpty ? null : queue[index],
      isPlaying: true,
      queue: queue,
      queueIndex: index,
      epoch: 1,
      version: version,
      queueLocked: locked,
      causedByCmdId: causedBy,
    );
    _states.add(_current);
  }

  void answer(String cmdId, {required bool ok, String? reason, String action = 'queue_remove'}) =>
      _results.add(CommandResult(ok: ok, action: action, reason: reason, cmdId: cmdId));

  void close() {
    _states.close();
    _results.close();
  }
}
