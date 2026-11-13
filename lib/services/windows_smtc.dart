import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

// The plugin-backed sink only exists where dart:io does; smtc_windows does not
// compile for the browser.
export 'windows_smtc_sink_stub.dart' if (dart.library.io) 'windows_smtc_sink_io.dart';

// =============================================================================
// windows_smtc.dart — System Media Transport Controls (Windows)
//
// Puts the current song, artwork, transport buttons and timeline into the
// Windows volume flyout and lock screen, and receives hardware media keys
// (which Windows routes to the app's SMTC session even when it is unfocused).
//
// The logic ([SmtcController]) talks to a small [SmtcSink], so it is tested
// with a fake; [SmtcWindowsSink] is the only code that touches smtc_windows.
// =============================================================================

enum SmtcButton { play, pause, next, previous, stop }

enum SmtcStatus { stopped, paused, playing }

class SmtcTrack {
  final String title;
  final String artist;
  final String album;
  final String? thumbnail;
  const SmtcTrack({required this.title, required this.artist, required this.album, this.thumbnail});

  @override
  bool operator ==(Object other) =>
      other is SmtcTrack &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(title, artist, album, thumbnail);
}

abstract class SmtcSink {
  Stream<SmtcButton> get buttons;
  Future<void> setTrack(SmtcTrack? track);
  Future<void> setStatus(SmtcStatus status);
  Future<void> setTimeline({required Duration position, required Duration duration});
  Future<void> dispose();
}

class SmtcTransport {
  final VoidCallback play;
  final VoidCallback pause;
  final VoidCallback next;
  final VoidCallback previous;
  final VoidCallback stop;
  const SmtcTransport({
    required this.play,
    required this.pause,
    required this.next,
    required this.previous,
    required this.stop,
  });
}

/// The thumbnail SMTC can load: an http(s) URL or a plain file path.
@visibleForTesting
String? smtcThumbnail(Uri? art) {
  if (art == null) return null;
  switch (art.scheme) {
    case 'http':
    case 'https':
      return art.toString();
    case 'file':
      return art.toFilePath();
    default:
      return null;
  }
}

@visibleForTesting
SmtcStatus smtcStatus(PlaybackState s) {
  if (s.processingState == AudioProcessingState.idle) return SmtcStatus.stopped;
  return s.playing ? SmtcStatus.playing : SmtcStatus.paused;
}

/// Mirrors the audio handler's streams into [sink] and routes its buttons to
/// [transport]. Windows extrapolates the position while playing, so the
/// timeline is only re-sent on track, play/pause and seek changes.
class SmtcController {
  SmtcController({
    required this.sink,
    required this.transport,
    required Stream<MediaItem?> mediaItem,
    required Stream<PlaybackState> playbackState,
  }) {
    _subs
      ..add(mediaItem.listen(_onItem))
      ..add(playbackState.listen(_onState))
      ..add(sink.buttons.listen(_onButton));
  }

  final SmtcSink sink;
  final SmtcTransport transport;
  final List<StreamSubscription<Object?>> _subs = [];

  SmtcTrack? _track;
  Duration _duration = Duration.zero;
  SmtcStatus? _status;
  Duration _position = Duration.zero;
  DateTime? _positionAt;

  /// A position this far from where playback should be is a seek.
  static const seekTolerance = Duration(seconds: 2);

  void _onItem(MediaItem? item) {
    final track = item == null
        ? null
        : SmtcTrack(
            title: item.title,
            artist: item.artist ?? '',
            album: item.album ?? '',
            thumbnail: smtcThumbnail(item.artUri),
          );
    final duration = item?.duration ?? Duration.zero;
    final changed = track != _track;
    final durationChanged = duration != _duration;
    _track = track;
    _duration = duration;
    if (changed) {
      // A new song starts at zero, not where the last one stopped.
      _position = Duration.zero;
      _positionAt = null;
    }
    if (changed) unawaited(_safe(() => sink.setTrack(track)));
    if (changed || durationChanged) _sendTimeline();
  }

  void _onState(PlaybackState s) {
    final status = smtcStatus(s);
    final expected = _expectedPosition();
    final seeked = (s.updatePosition - expected).abs() > seekTolerance;
    _position = s.updatePosition;
    _positionAt = DateTime.now();
    if (status != _status) {
      _status = status;
      unawaited(_safe(() => sink.setStatus(status)));
      _sendTimeline();
    } else if (seeked) {
      _sendTimeline();
    }
  }

  Duration _expectedPosition() {
    final at = _positionAt;
    if (at == null || _status != SmtcStatus.playing) return _position;
    return _position + DateTime.now().difference(at);
  }

  void _sendTimeline() {
    if (_track == null) return;
    unawaited(_safe(() => sink.setTimeline(position: _position, duration: _duration)));
  }

  void _onButton(SmtcButton b) {
    switch (b) {
      case SmtcButton.play:
        transport.play();
      case SmtcButton.pause:
        transport.pause();
      case SmtcButton.next:
        transport.next();
      case SmtcButton.previous:
        transport.previous();
      case SmtcButton.stop:
        transport.stop();
    }
  }

  // The flyout is a courtesy: a failure must never reach playback.
  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('[SMTC] $e');
    }
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _safe(sink.dispose);
  }
}

