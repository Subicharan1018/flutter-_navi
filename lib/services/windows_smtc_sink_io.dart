import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../utils/platform_utils.dart';
import 'windows_smtc.dart';

/// The real thing, over smtc_windows (Rust, via flutter_rust_bridge).
///
/// Only compiled where `dart:io` exists: smtc_windows does not build for the
/// web (its generated bindings use BigInt there), so browsers get
/// `windows_smtc_sink_stub.dart` instead.
class SmtcWindowsSink implements SmtcSink {
  SmtcWindowsSink._(this._smtc);
  final SMTCWindows _smtc;

  static Future<SmtcWindowsSink?> create() async {
    if (!PlatformUtils.isWindows) return null;
    try {
      await SMTCWindows.initialize();
      return SmtcWindowsSink._(SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      ));
    } catch (e) {
      debugPrint('[SMTC] unavailable: $e');
      return null;
    }
  }

  @override
  Stream<SmtcButton> get buttons => _smtc.buttonPressStream.expand((b) => switch (b) {
    PressedButton.play => [SmtcButton.play],
    PressedButton.pause => [SmtcButton.pause],
    PressedButton.next => [SmtcButton.next],
    PressedButton.previous => [SmtcButton.previous],
    PressedButton.stop => [SmtcButton.stop],
    _ => const <SmtcButton>[],
  });

  @override
  Future<void> setTrack(SmtcTrack? t) => t == null
      ? _smtc.clearMetadata()
      : _smtc.updateMetadata(MusicMetadata(
          title: t.title,
          artist: t.artist,
          album: t.album,
          albumArtist: t.artist,
          thumbnail: t.thumbnail,
        ));

  @override
  Future<void> setStatus(SmtcStatus s) => _smtc.setPlaybackStatus(switch (s) {
    SmtcStatus.stopped => PlaybackStatus.stopped,
    SmtcStatus.paused => PlaybackStatus.paused,
    SmtcStatus.playing => PlaybackStatus.playing,
  });

  @override
  Future<void> setTimeline({required Duration position, required Duration duration}) =>
      _smtc.updateTimeline(PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: duration.inMilliseconds,
        positionMs: position.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: duration.inMilliseconds,
      ));

  @override
  Future<void> dispose() => _smtc.dispose();
}
