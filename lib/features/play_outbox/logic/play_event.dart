// The vocabulary of the play-event log (schema_version 2): what kind of event it
// is, where the song came from, and how long the listener really listened.
//
// Pure Dart: no Flutter, no Riverpod, so every rule here is unit-tested.
// The server side of this contract is tool/server/play-events-v2/ and the field
// list is docs/play-event-schema.md.

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version written in every event. The server accepts older shapes too.
const int kPlayEventSchemaVersion = 2;

/// One thing the app reports about listening.
enum PlayEventType {
  /// A song has been playing for a few seconds (a crash-proof "it began").
  start,

  /// The listener moved on before the song ended.
  skip,

  /// The song played to its natural end.
  complete,

  /// Repeat-one looped the song again.
  replay,

  /// The listener scrubbed to another position.
  seek,

  /// The listener added, removed, moved or "played next" a queue entry.
  queueEdit;

  String get wire => switch (this) {
        PlayEventType.queueEdit => 'queue_edit',
        _ => name,
      };

  /// Events that finish a play (one row in the server's `play_events`).
  bool get isFinish => this == skip || this == complete || this == replay;
}

/// Where a play came from.
enum PlaySource {
  smartShuffle('smart_shuffle'),
  autoplay('autoplay'),
  album('album'),
  playlist('playlist'),
  search('search'),
  jam('jam'),
  remote('remote'),
  queue('queue'),
  radio('radio'),
  library('library'),
  download('download'),
  other('other');

  const PlaySource(this.wire);
  final String wire;
}

/// How the queue was edited.
enum QueueEditKind {
  add('add'),
  remove('remove'),
  reorder('reorder'),
  playNext('play_next');

  const QueueEditKind(this.wire);
  final String wire;
}

/// Why a song is where it is in the queue: the slot, score and engine the server
/// gave it, and whether it is one of the holdout picks (placed without the AI).
@immutable
class PlayOrigin {
  const PlayOrigin({
    required this.source,
    this.slot,
    this.score,
    this.servedBy,
    this.servedId,
    this.holdout = false,
  });

  final PlaySource source;

  /// Zero-based position within the served batch.
  final int? slot;
  final double? score;

  /// The server's engine (`v3`, `v3+ai`, `legacy`, ...) or `holdout_random`.
  final String? servedBy;

  /// The `served_id` /next returned: joins this play to the server's record of what it served.
  final String? servedId;
  final bool holdout;

  PlayOrigin copyWith({PlaySource? source, int? slot, String? servedBy, bool? holdout}) => PlayOrigin(
        source: source ?? this.source,
        slot: slot ?? this.slot,
        score: score,
        servedBy: servedBy ?? this.servedBy,
        servedId: servedId,
        holdout: holdout ?? this.holdout,
      );
}

/// Maps the player's transition context to a [PlaySource] for songs the server
/// did not place. [serverPlaced] wins over the context.
PlaySource sourceFromContext(String context, {required bool serverPlaced, bool remote = false}) {
  if (remote) return PlaySource.remote;
  if (serverPlaced) return PlaySource.smartShuffle;
  return switch (context) {
    'playlist' => PlaySource.playlist,
    'album' => PlaySource.album,
    'search' => PlaySource.search,
    'jam' => PlaySource.jam,
    'user_queue' => PlaySource.queue,
    'user_selected' => PlaySource.library,
    'manual_next' => PlaySource.queue,
    'autoplay' => PlaySource.autoplay,
    _ => PlaySource.other,
  };
}

/// 5 % of smart-shuffle slots are placed WITHOUT the AI (a random spot in the
/// batch) and flagged, so a later evaluation has a fair baseline to compare to.
class HoldoutPolicy {
  const HoldoutPolicy._();

  static const double rate = 0.05;

  /// Same session and ordinal always answer the same, so a retry or a rebuild of
  /// the queue never changes which songs are held out. FNV-1a over the text.
  static bool isHoldout(String sessionId, int ordinal, {double rate = HoldoutPolicy.rate}) {
    if (sessionId.isEmpty || ordinal < 0) return false;
    return (_fnv('$sessionId:$ordinal') % 10000) < (rate * 10000).round();
  }

  /// Which of the [span] later places a held-out song is taken from (0-based).
  static int offset(String sessionId, int ordinal, int span) =>
      span <= 0 ? 0 : _fnv('o:$sessionId:$ordinal') % span;

  static int _fnv(String text) {
    var h = 0x811c9dc5;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}

/// What a finished stretch of listening amounts to.
@immutable
class ListenResult {
  const ListenResult({
    required this.secondsPlayed,
    required this.seeks,
    required this.maxPositionS,
    required this.hadEvidence,
  });

  /// Seconds of audio the listener actually heard (position moving forward while
  /// playing). A scrub is not listening; time paused is not listening.
  final double secondsPlayed;
  final int seeks;
  final double maxPositionS;

  /// False when the tracker never saw this play, so the numbers say nothing.
  final bool hadEvidence;

  static const none = ListenResult(secondsPlayed: 0, seeks: 0, maxPositionS: 0, hadEvidence: false);
}

/// A thing the tracker noticed while the position moved.
sealed class ListenSignal {
  const ListenSignal();
}

class SeekSignal extends ListenSignal {
  const SeekSignal(this.fromMs, this.toMs);
  final int fromMs;
  final int toMs;
}

/// The position wrapped back to the start near the end: repeat-one looped.
class LoopSignal extends ListenSignal {
  const LoopSignal();
}

/// Measures real listening from the position stream.
///
/// Feed it every position tick; ask [finish] when the play ends. A step forward of
/// at most [maxStep] counts as listening, a bigger jump (either way) is a seek.
class ListenTracker {
  ListenTracker({this.maxStep = const Duration(seconds: 3)});

  final Duration maxStep;

  String? _songId;
  int _durationS = 0;
  double _played = 0;
  int _seeks = 0;
  double _maxPos = 0;
  Duration? _last;
  bool _open = false;

  bool get isOpen => _open;
  String? get songId => _songId;

  /// A new play starts; whatever was open is discarded.
  void begin(String songId, int durationS) {
    _songId = songId;
    _durationS = durationS;
    _played = 0;
    _seeks = 0;
    _maxPos = 0;
    _last = null;
    _open = true;
  }

  /// A new lap of the same song (repeat-one).
  void restartLap() => begin(_songId ?? '', _durationS);

  ListenSignal? onPosition(Duration position, {required bool playing}) {
    if (!_open) return null;
    final last = _last;
    _last = position;
    final posS = position.inMilliseconds / 1000.0;
    if (posS > _maxPos) _maxPos = posS;
    if (last == null) return null;
    final step = position - last;
    if (step.isNegative || step > maxStep) {
      // Near the end and back to the start: a loop, not a scrub.
      if (_durationS > 0 && last.inSeconds >= _durationS - 4 && position.inSeconds <= 3) {
        return const LoopSignal();
      }
      _seeks++;
      return SeekSignal(last.inMilliseconds, position.inMilliseconds);
    }
    if (playing) _played += step.inMilliseconds / 1000.0;
    return null;
  }

  /// Ends the play and returns what was heard. Safe to call twice: the second
  /// call has no evidence (the first one consumed it).
  ListenResult finish() {
    if (!_open) return ListenResult.none;
    _open = false;
    return ListenResult(secondsPlayed: _played, seeks: _seeks, maxPositionS: _maxPos, hadEvidence: true);
  }
}

/// The verdict on one ended play.
@immutable
class EndVerdict {
  const EndVerdict(this.type, this.endReason, this.ratio, this.secondsPlayed);
  final PlayEventType type;

  /// The legacy `end_reason` ('natural' | 'fwdbtn' | 'autoskip') old servers read.
  final String endReason;
  final double ratio;
  final double secondsPlayed;
}

/// Decides what to report for a song that just ended, or null when there is nothing
/// true to report.
///
/// The old app wrote "finished naturally at 0 %" whenever the advance came from a
/// listener that did not know the position. That cannot happen, so a natural end with
/// (almost) nothing heard is dropped, not recorded; a natural end that was really a
/// partial listen is reported as the skip it was.
///
/// [snapshotSeconds] is the last position the player reported, used only when the
/// tracker never saw the play.
EndVerdict? classifyEnd({
  required ListenResult heard,
  required int durationS,
  required bool naturalHint,
  double snapshotSeconds = 0,
}) {
  // The tracker wins when it saw the play; with no ticks at all the player's last position is all there is.
  final trusted = heard.hadEvidence && (heard.secondsPlayed > 0 || heard.maxPositionS > 0);
  var seconds = trusted ? heard.secondsPlayed : snapshotSeconds;
  if (seconds.isNaN || seconds < 0) seconds = 0;
  if (durationS > 0) seconds = seconds > durationS * 1.05 ? durationS.toDouble() : seconds;
  final ratio = durationS > 0 ? (seconds / durationS).clamp(0.0, 1.0) : (naturalHint && seconds >= 30 ? 1.0 : 0.0);

  if (naturalHint) {
    if (ratio >= 0.5) return EndVerdict(PlayEventType.complete, 'natural', ratio, seconds);
    if (seconds >= 1.0) return EndVerdict(PlayEventType.skip, 'autoskip', ratio, seconds);
    return null; // "natural" with nothing heard: not a real listen
  }
  return EndVerdict(PlayEventType.skip, 'fwdbtn', ratio, seconds);
}

/// App version and platform for every event, so the server can report data quality
/// per client build.
class ClientInfo {
  const ClientInfo._();

  static String version = '';
  static bool _started = false;

  static String get platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Reads the version once, without making callers wait for it.
  static void ensure() {
    if (_started || version.isNotEmpty) return;
    _started = true;
    PackageInfo.fromPlatform().then<void>(
      (i) => version = i.version,
      onError: (Object _) => _started = false, // try again next time
    );
  }
}
