import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/desktop_tray.dart';
import 'package:navivibe/services/windows_smtc.dart';

class _FakeSink implements SmtcSink {
  final buttonsCtl = StreamController<SmtcButton>.broadcast();
  final calls = <String>[];
  @override
  Stream<SmtcButton> get buttons => buttonsCtl.stream;
  @override
  Future<void> setTrack(SmtcTrack? t) async => calls.add('track:${t?.title}:${t?.thumbnail}');
  @override
  Future<void> setStatus(SmtcStatus s) async => calls.add('status:${s.name}');
  @override
  Future<void> setTimeline({required Duration position, required Duration duration}) async =>
      calls.add('timeline:${position.inSeconds}/${duration.inSeconds}');
  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late _FakeSink sink;
  late StreamController<MediaItem?> items;
  late StreamController<PlaybackState> states;
  late List<String> pressed;
  late SmtcController c;

  setUp(() {
    sink = _FakeSink();
    items = StreamController<MediaItem?>();
    states = StreamController<PlaybackState>();
    pressed = [];
    c = SmtcController(
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
  });

  tearDown(() async {
    await c.dispose();
    await items.close();
    await states.close();
  });

  PlaybackState playing(int sec, {bool on = true}) => PlaybackState(
    processingState: AudioProcessingState.ready,
    playing: on,
    updatePosition: Duration(seconds: sec),
  );

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('a new song sends metadata and timeline once', () async {
    items.add(MediaItem(id: '1', title: 'Song', artist: 'Band', duration: const Duration(seconds: 200),
        artUri: Uri.parse('https://x/art.jpg')));
    await pump();
    expect(sink.calls, ['track:Song:https://x/art.jpg', 'timeline:0/200']);
    items.add(MediaItem(id: '1', title: 'Song', artist: 'Band', duration: const Duration(seconds: 200),
        artUri: Uri.parse('https://x/art.jpg')));
    await pump();
    expect(sink.calls.length, 2);
  });

  test('play, pause and idle map to SMTC status', () async {
    items.add(const MediaItem(id: '1', title: 'S', duration: Duration(seconds: 10)));
    states.add(playing(0));
    states.add(playing(1, on: false));
    states.add(PlaybackState());
    await pump();
    expect(sink.calls.where((x) => x.startsWith('status')), ['status:playing', 'status:paused', 'status:stopped']);
  });

  test('ticking position is not re-sent, a seek is', () async {
    items.add(const MediaItem(id: '1', title: 'S', duration: Duration(seconds: 100)));
    states.add(playing(0));
    await pump();
    final before = sink.calls.length;
    states.add(playing(0)); // same state, same position
    await pump();
    expect(sink.calls.length, before);
    states.add(playing(60)); // jumped
    await pump();
    expect(sink.calls.last, 'timeline:60/100');
  });

  test('buttons reach the transport', () async {
    for (final b in SmtcButton.values) {
      sink.buttonsCtl.add(b);
    }
    await pump();
    expect(pressed, ['play', 'pause', 'next', 'previous', 'stop']);
  });

  test('thumbnail accepts http and file, nothing else', () {
    expect(smtcThumbnail(Uri.parse('http://a/b')), 'http://a/b');
    expect(smtcThumbnail(Uri.file('C:/x/y.jpg', windows: true)), contains('y.jpg'));
    expect(smtcThumbnail(Uri.parse('content://a')), isNull);
    expect(smtcThumbnail(null), isNull);
  });

  test('tray tooltip shows song and artist, capped at 127', () {
    expect(DesktopTray.tooltipFor(), 'NaviVibe');
    expect(DesktopTray.tooltipFor(title: 'A', artist: 'B'), 'A · B');
    expect(DesktopTray.tooltipFor(title: 'A'), 'A');
    expect(DesktopTray.tooltipFor(title: 'x' * 300).length, 127);
  });
}
