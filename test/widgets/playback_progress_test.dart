import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/player_controls.dart';

/// A player that reports whatever position/duration the test sets and
/// records every seek.
class _FakePlayer extends Fake implements AudioPlayer {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration?>.broadcast();
  Duration _position = Duration.zero;
  Duration? _duration;
  final seeks = <Duration>[];
  bool isPlaying = true;

  @override
  bool get playing => isPlaying;

  @override
  Duration get position => _position;
  @override
  Duration? get duration => _duration;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration?> get durationStream => _dur.stream;

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position!);
    _position = position;
    _pos.add(position);
  }

  void setPosition(Duration p) {
    _position = p;
    _pos.add(p);
  }

  void setDuration(Duration? d) {
    _duration = d;
    _dur.add(d);
  }

  Future<void> close() async {
    await _pos.close();
    await _dur.close();
  }
}

Song _song(String id, int seconds) => Song(
  id: id,
  title: id,
  artist: 'a',
  album: 'b',
  coverArt: id,
  duration: seconds,
  track: 1,
  year: 2020,
);

const _s = Duration(seconds: 1);

void main() {
  group('ProgressTimeline', () {
    test('uses the song length when the player disagrees (1:30 vs 4:00)', () {
      final t = ProgressTimeline.resolve(
        songSeconds: 240,
        playerDuration: const Duration(seconds: 90),
      );
      expect(t.total, const Duration(seconds: 240));
    });

    test('prefers the player length only when within 2 s of the song', () {
      final close = ProgressTimeline.resolve(
        songSeconds: 240,
        playerDuration: const Duration(milliseconds: 241500),
      );
      expect(close.total, const Duration(milliseconds: 241500));
      expect(close.scale, 1.0);
      final far = ProgressTimeline.resolve(
        songSeconds: 240,
        playerDuration: const Duration(seconds: 243),
      );
      expect(far.total, const Duration(seconds: 240));
    });

    test('falls back to the player length only when the song has none', () {
      final t = ProgressTimeline.resolve(
        songSeconds: 0,
        playerDuration: const Duration(seconds: 200),
      );
      expect(t.total, const Duration(seconds: 200));
      expect(
        ProgressTimeline.resolve(songSeconds: 0, playerDuration: null).total,
        Duration.zero,
      );
    });

    test('rescales positions both ways when the timelines differ', () {
      final t = ProgressTimeline.resolve(
        songSeconds: 240,
        playerDuration: const Duration(seconds: 90),
      );
      // 45 s on the player's 90 s timeline is the middle of the 4:00 song.
      expect(t.toReal(const Duration(seconds: 45)), const Duration(seconds: 120));
      // Seeking to 3:00 asks the player for 67.5 s of its own timeline.
      expect(
        t.toPlayer(const Duration(seconds: 180)),
        const Duration(milliseconds: 67500),
      );
    });

    test('positions are clamped to the song', () {
      final t = ProgressTimeline.resolve(songSeconds: 240, playerDuration: null);
      expect(t.toReal(const Duration(seconds: 999)), const Duration(seconds: 240));
      expect(t.toReal(const Duration(seconds: -5)), Duration.zero);
      expect(t.toPlayer(const Duration(seconds: 999)), const Duration(seconds: 240));
    });
  });

  group('PlaybackProgress', () {
    test('elapsed, remaining and fraction come from one model', () {
      final p = PlaybackProgress(
        ProgressTimeline.resolve(songSeconds: 240, playerDuration: null),
        const Duration(seconds: 60),
      );
      expect(p.fraction, 0.25);
      expect(p.remaining, const Duration(seconds: 180));
    });

    test('unknown length reads as empty, never NaN', () {
      const p = PlaybackProgress(ProgressTimeline.unknown(), _s);
      expect(p.fraction, 0.0);
    });
  });

  group('PlaybackProgressBuilder', () {
    Future<List<PlaybackProgress>> pumpBuilder(
      WidgetTester tester,
      _FakePlayer player,
      Song song,
    ) async {
      final seen = <PlaybackProgress>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackProgressBuilder(
            player: player,
            song: song,
            builder: (_, p) {
              seen.add(p);
              return const SizedBox();
            },
          ),
        ),
      );
      return seen;
    }

    testWidgets('a 1:30 player duration still yields a 4:00 bar', (tester) async {
      final player = _FakePlayer()..setDuration(const Duration(seconds: 90));
      addTearDown(player.close);
      final seen = await pumpBuilder(tester, player, _song('a', 240));
      expect(seen.last.total, const Duration(seconds: 240));
    });

    testWidgets('seeking to 3:00 lands at 3:00 of the song', (tester) async {
      final player = _FakePlayer();
      addTearDown(player.close);
      final seen = await pumpBuilder(tester, player, _song('a', 240));
      // Player agrees with the song: the seek goes straight through.
      seen.last.seekTo(player, const Duration(minutes: 3));
      expect(player.seeks.single, const Duration(minutes: 3));
    });

    testWidgets('seek is translated when the player timeline is stretched', (
      tester,
    ) async {
      final player = _FakePlayer()..setDuration(const Duration(seconds: 90));
      addTearDown(player.close);
      final seen = await pumpBuilder(tester, player, _song('a', 240));
      seen.last.seekTo(player, const Duration(minutes: 3));
      expect(player.seeks.single, const Duration(milliseconds: 67500));
    });

    testWidgets('position advances continuously through a hand-over', (
      tester,
    ) async {
      final player = _FakePlayer();
      addTearDown(player.close);
      final seen = await pumpBuilder(tester, player, _song('a', 240));
      Future<void> tick(Duration p) async {
        player.setPosition(p);
        await tester.pump();
        await tester.pump();
      }

      // Volume dips during a crossfade never touch position; each tick
      // continues from where the last one was, with no jump back to zero.
      await tick(const Duration(seconds: 100));
      expect(seen.last.position, const Duration(seconds: 100));
      await tick(const Duration(milliseconds: 100500));
      expect(seen.last.position, const Duration(milliseconds: 100500));
      await tick(const Duration(seconds: 101));
      expect(seen.last.position, const Duration(seconds: 101));
    });

    testWidgets('a rewind to zero while paused shows, while playing it does not', (
      tester,
    ) async {
      final player = _FakePlayer();
      addTearDown(player.close);
      final seen = await pumpBuilder(tester, player, _song('a', 240));
      player.setPosition(const Duration(seconds: 240));
      await tester.pump();
      await tester.pump();
      expect(seen.last.position, const Duration(seconds: 240));

      // A zero emitted while playing is a source switch: keep the bar.
      player.setPosition(Duration.zero);
      await tester.pump();
      await tester.pump();
      expect(seen.last.position, const Duration(seconds: 240));

      // Paused at the end of the queue: the rewind is real.
      player.isPlaying = false;
      player.setPosition(Duration.zero);
      await tester.pump();
      await tester.pump();
      expect(seen.last.position, Duration.zero);
    });

    testWidgets('a track change resets position and length', (tester) async {
      final player = _FakePlayer()..setDuration(const Duration(seconds: 90));
      addTearDown(player.close);
      final song = ValueNotifier<Song>(_song('a', 240));
      final seen = <PlaybackProgress>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<Song>(
            valueListenable: song,
            builder: (_, s, _) => PlaybackProgressBuilder(
              player: player,
              song: s,
              builder: (_, p) {
                seen.add(p);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      player.setPosition(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump();
      // 30 s of the stretched 1:30 timeline is 80 s of the 4:00 song.
      expect(seen.last.position, const Duration(seconds: 80));

      song.value = _song('b', 180);
      await tester.pump();
      await tester.pump();
      // The old track's 1:30 must not size the new bar, and the old
      // position must not carry over.
      expect(seen.last.total, const Duration(seconds: 180));
      expect(seen.last.position, Duration.zero);
    });
  });

  group('Scrubber and mini player share one model', () {
    testWidgets('same labels and fraction from the same player', (tester) async {
      final player = _FakePlayer()..setDuration(const Duration(seconds: 90));
      addTearDown(player.close);
      final song = _song('a', 240);
      PlaybackProgress? mini;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                width: 300,
                child: Scrubber(player: player, song: song, showQuality: false),
              ),
              PlaybackProgressBuilder(
                player: player,
                song: song,
                builder: (_, p) {
                  mini = p;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      player.setPosition(const Duration(seconds: 30)); // 1/3 of the 1:30 timeline
      await tester.pump(const Duration(milliseconds: 300));
      // Rescaled: 30 s of 90 s is 80 s of the 4:00 song.
      expect(find.text('1:20'), findsOneWidget);
      expect(find.text('-2:40'), findsOneWidget);
      expect(mini!.position, const Duration(seconds: 80));
      expect(mini!.remaining, const Duration(seconds: 160));
      expect(mini!.fraction, closeTo(1 / 3, 1e-9));
    });
  });
}
