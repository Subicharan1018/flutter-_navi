import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/media_key_gate.dart';
import 'package:navivibe/services/windows_smtc.dart';

class _Sink implements SmtcSink {
  final ctl = StreamController<SmtcButton>.broadcast();
  final statuses = <SmtcStatus>[];
  @override
  Stream<SmtcButton> get buttons => ctl.stream;
  @override
  Future<void> setTrack(SmtcTrack? t) async {}
  @override
  Future<void> setStatus(SmtcStatus s) async => statuses.add(s);
  @override
  Future<void> setTimeline({required Duration position, required Duration duration}) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test('a press seen by SMTC and by the focused window acts once', () {
    var now = DateTime(2026);
    final gate = MediaKeyGate(clock: () => now);
    var n = 0;
    expect(gate.handle(MediaKeyAction.pause, () => n++), isTrue);
    now = now.add(const Duration(milliseconds: 20));
    expect(gate.handle(MediaKeyAction.playPause, () => n++), isFalse);
    expect(n, 1);
    now = now.add(const Duration(seconds: 1));
    expect(gate.handle(MediaKeyAction.playPause, () => n++), isTrue);
    expect(n, 2);
  });

  test('next right after play/pause is a different key and runs', () {
    final gate = MediaKeyGate(clock: () => DateTime(2026));
    var n = 0;
    gate.handle(MediaKeyAction.playPause, () => n++);
    gate.handle(MediaKeyAction.next, () => n++);
    expect(n, 2);
  });

  test('in-app key events step aside once SMTC owns the keys', () {
    final gate = MediaKeyGate()..smtcActive = true;
    var n = 0;
    expect(gate.handleInApp(MediaKeyAction.playPause, () => n++), isFalse);
    gate.smtcActive = false;
    expect(gate.handleInApp(MediaKeyAction.playPause, () => n++), isTrue);
    expect(n, 1);
  });

  test('an SMTC play press reaches the transport exactly once', () async {
    final sink = _Sink();
    final items = StreamController<MediaItem?>();
    final states = StreamController<PlaybackState>();
    final pressed = <String>[];
    final c = SmtcController(
      gate: MediaKeyGate(),
      sink: sink,
      mediaItem: items.stream,
      playbackState: states.stream,
      transport: SmtcTransport(
        play: () => pressed.add('play'),
        pause: () => pressed.add('pause'),
        next: () => pressed.add('next'),
        previous: () => pressed.add('previous'),
        stop: () => pressed.add('stop'),
      ),
    );
    sink.ctl.add(SmtcButton.play);
    sink.ctl.add(SmtcButton.pause); // the twin of the same press
    await Future<void>.delayed(Duration.zero);
    expect(pressed, ['play']);
    await c.dispose();
    await items.close();
    await states.close();
  });

  test('a stopped session with a song loaded is shown as paused, so Windows keeps routing keys to it', () async {
    final sink = _Sink();
    final items = StreamController<MediaItem?>();
    final states = StreamController<PlaybackState>();
    final c = SmtcController(
      sink: sink,
      mediaItem: items.stream,
      playbackState: states.stream,
      transport: SmtcTransport(play: () {}, pause: () {}, next: () {}, previous: () {}, stop: () {}),
    );
    items.add(const MediaItem(id: '1', title: 'Song'));
    states.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
    await Future<void>.delayed(Duration.zero);
    expect(sink.statuses, [SmtcStatus.paused]);
    await c.dispose();
    await items.close();
    await states.close();
  });
}
