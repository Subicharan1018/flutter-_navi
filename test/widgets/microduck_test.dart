import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' show PictureRecorder;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/widgets/mascot/chat/chat_intent.dart';
import 'package:navivibe/widgets/mascot/microduck.dart';
import 'package:navivibe/widgets/mascot/microduck_mesh.dart';
import 'package:navivibe/widgets/mascot/microduck_painter.dart';
import 'package:navivibe/widgets/mascot/microduck_rig.dart';
import 'package:navivibe/widgets/mascot/microduck_pose.dart';
import 'package:navivibe/widgets/mascot/microduck_strip.dart';
import 'package:navivibe/widgets/mascot/microduck_talk.dart';

void main() {
  group('pose selection', () {
    final noon = DateTime(2026, 1, 1, 12);
    final night = DateTime(2026, 1, 1, 2, 30);

    test('plays: walks; paused: stands', () {
      expect(resolveMicroduckPose(playing: true, now: noon), MicroduckPose.walk);
      expect(resolveMicroduckPose(playing: false, now: noon), MicroduckPose.idle);
    });

    test('sleeps from 00:00 to 04:59, wakes at 05:00', () {
      expect(isMicroduckNight(DateTime(2026, 1, 1, 0)), isTrue);
      expect(isMicroduckNight(DateTime(2026, 1, 1, 4, 59)), isTrue);
      expect(isMicroduckNight(DateTime(2026, 1, 1, 5)), isFalse);
      expect(resolveMicroduckPose(playing: true, now: night), MicroduckPose.sleep);
      expect(resolveMicroduckPose(playing: true, now: night, sleepsAtNight: false), MicroduckPose.walk);
    });

    test('dances only when allowed, and only while playing', () {
      expect(resolveMicroduckPose(playing: true, now: noon, allowDance: true), MicroduckPose.dance);
      expect(resolveMicroduckPose(playing: true, now: noon), MicroduckPose.walk);
      expect(resolveMicroduckPose(playing: false, now: noon, allowDance: true), MicroduckPose.idle);
    });

    test('paused sits on the mini player, stands elsewhere', () {
      expect(resolveMicroduckPose(playing: false, now: noon, sitWhenPaused: true), MicroduckPose.sit);
      expect(resolveMicroduckPose(playing: false, now: noon), MicroduckPose.idle);
      expect(resolveMicroduckPose(playing: true, now: noon, sitWhenPaused: true), MicroduckPose.walk);
    });

    test('faster songs move bigger', () {
      expect(danceEnergy(70), lessThan(danceEnergy(100)));
      expect(danceEnergy(100), lessThan(danceEnergy(150)));
      expect(danceEnergy(300), lessThanOrEqualTo(1.25));
    });

    test('reduced motion gets a still pose', () {
      expect(resolveMicroduckPose(playing: true, now: noon, reducedMotion: true, allowDance: true),
          MicroduckPose.idle);
      expect(resolveMicroduckPose(playing: true, now: night, reducedMotion: true), MicroduckPose.sleep);
    });

    test('tempo must be believable; fast songs dance half time, slow ones double', () {
      expect(danceBpm(null), isNull);
      expect(danceBpm(0), isNull);
      expect(danceBpm(120), 120);
      expect(danceBeatSeconds(120), closeTo(0.5, 1e-9));
      expect(danceBeatSeconds(170), closeTo(2 * 60 / 170, 1e-9));
      expect(danceBeatSeconds(60), closeTo(0.5, 1e-9));
      expect(danceBeatSeconds(150), closeTo(0.4, 1e-9));
      expect(danceBeatSeconds(75), closeTo(0.8, 1e-9));
    });

    test('names are trimmed, capped and never empty', () {
      expect(cleanMicroduckName(null), defaultMicroduckName);
      expect(cleanMicroduckName('   '), defaultMicroduckName);
      expect(cleanMicroduckName('  Quackers '), 'Quackers');
      expect(cleanMicroduckName('x' * 60).length, maxMicroduckNameLength);
    });

    test('empty-state duck is stable per day and shows on some messages', () {
      final d = DateTime(2026, 3, 3, 9);
      expect(showDuckInEmptyState('No songs', d), showDuckInEmptyState('No songs', DateTime(2026, 3, 3, 22)));
      final shown = List.generate(60, (i) => showDuckInEmptyState('t$i', d)).where((b) => b).length;
      expect(shown, inInclusiveRange(8, 35));
    });
  });

  group('dance is locked to the beat', () {
    // Bar 3 of a song is the first phrase's closing move, the bounce-jump:
    // feet on the ground and knees fully bent exactly on each beat, airborne
    // between them. So where the pose is "down" tells where the beat is.
    const jumpBars = [3, 15, 27]; // phrase % 3 == 0 -> bounce-jump
    const offset = 0.37; // first beat falls 0.37 s into the song

    for (final bpm in [60, 75, 80, 100, 120, 140, 150, 170, 200]) {
      test('$bpm bpm: down-step on every beat, up between, also after a seek', () {
        final beat = danceBeatSeconds(bpm);
        for (final bar in jumpBars) {
          // A fresh rig each time stands in for a seek: position is all it needs.
          final rig = MicroduckRig();
          final input = MicroduckInput()..beatOffset = offset;
          for (final k in [1, 2, 3]) {
            final onBeat = offset + (bar * 4 + k) * beat;
            input.audioPos = onBeat;
            rig.solve(MicroduckPose.dance, onBeat, beat, input);
            expect(rig.pose.v[RigPose.y], closeTo(0, 1e-6), reason: 'bpm $bpm bar $bar beat $k feet down');
            expect(rig.pose.v[RigPose.kneeL], closeTo(1.07, 1e-6), reason: 'knees fully bent on the beat');

            final between = onBeat + beat / 2;
            input.audioPos = between;
            rig.solve(MicroduckPose.dance, between, beat, input);
            expect(rig.pose.v[RigPose.y], greaterThan(1.0), reason: 'bpm $bpm airborne mid-beat');
          }
        }
      });
    }

    for (final bpm in [70, 100, 120, 150, 180]) {
      test('$bpm bpm: the neck stretches up on the bar line, most on a phrase\'s first beat', () {
        final beat = danceBeatSeconds(bpm);
        double neckAt(double beats) {
          final rig = MicroduckRig();
          final input = MicroduckInput()..audioPos = beats * beat;
          rig.solve(MicroduckPose.dance, beats * beat, beat, input);
          return rig.pose.v[RigPose.neck];
        }

        expect(neckAt(32), closeTo(0.4, 1e-6), reason: 'phrase downbeat');
        expect(neckAt(36), closeTo(0.15, 1e-6), reason: 'an ordinary bar line');
        expect(neckAt(38.5), closeTo(0, 1e-6), reason: 'mid-bar, relaxed');
        // The same after a seek anywhere in the song.
        expect(neckAt(32 + 16 * 7), closeTo(0.4, 1e-6));
      });
    }

    test('moves change on bar lines and the big ones close each phrase', () {
      for (var bar = 0; bar < 48; bar++) {
        final big = const {2, 3, 4}.contains(MicroduckRig.moveForBar(bar));
        expect(big, (bar & 3) == 3, reason: 'bar $bar');
      }
      expect({for (var b = 0; b < 48; b++) MicroduckRig.moveForBar(b)}.length, 9, reason: 'all nine moves appear');
    });

    test('a pause does not move the beat: same position, same pose', () {
      final a = MicroduckRig(), b = MicroduckRig();
      final input = MicroduckInput()..audioPos = 41.3;
      a.solve(MicroduckPose.dance, 1.0, 0.5, input);
      b.solve(MicroduckPose.dance, 99.0, 0.5, input);
      for (var i = 0; i < RigPose.count; i++) {
        expect(a.pose.v[i], closeTo(b.pose.v[i], 1e-9));
      }
    });

    test('danceBeats counts stepping beats from the first beat', () {
      expect(danceBeats(0.37, 120, offsetSeconds: 0.37), closeTo(0, 1e-9));
      expect(danceBeats(0.37 + 0.5 * 7, 120, offsetSeconds: 0.37), closeTo(7, 1e-9));
      expect(danceBeats(1.0, 170, offsetSeconds: 0), closeTo(1.0 / (2 * 60 / 170), 1e-9));
    });
  });

  group('talking', () {
    test('ordinals', () {
      expect([for (final n in [1, 2, 3, 4, 11, 12, 13, 21, 42, 101, 111]) ordinal(n)],
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '42nd', '101st', '111th']);
    });

    test('a well-played song gets the play-count line', () {
      const facts = MicroduckFacts(songId: 's', title: 'T', playCount: 41, composer: 'A. R. Rahman');
      expect(microduckComment(facts, DateTime(2026, 3, 3, 12)), 'Your 42nd play of this one!');
    });

    test('says nothing without facts, and at most something short', () {
      expect(microduckComment(const MicroduckFacts(songId: 's', title: 'T'), DateTime(2026, 3, 3, 12)), isNull);
      final line = microduckComment(
        const MicroduckFacts(songId: 's', title: 'T', composer: 'X', film: 'Y', year: 2020, bpm: 120),
        DateTime(2026, 3, 3, 12),
      )!;
      expect(line.length, lessThan(40));
    });

    test('speaks up on roughly a third of songs, the same way all day', () {
      final now = DateTime(2026, 3, 3, 9);
      final chatty = List.generate(90, (i) => microduckFeelsChatty('song$i', now)).where((b) => b).length;
      expect(chatty, inInclusiveRange(15, 45));
      expect(microduckFeelsChatty('song1', now), microduckFeelsChatty('song1', DateTime(2026, 3, 3, 23)));
    });

    test('describes the current song from local facts', () {
      final text = describeSong(
        title: 'Aga Naga',
        artist: 'A. R. Rahman',
        facts: const MicroduckFacts(songId: 's', title: 'Aga Naga', film: 'PS-1', year: 2022, playCount: 3, bpm: 98),
      );
      expect(text, contains('From “PS-1”'));
      expect(text, contains('3 times'));
      expect(text, contains('98 bpm'));
    });
  });

  group('chat routing', () {
    ChatIntent r(String s) => routeChat(s);

    test('quick chips and free text reach the right place', () {
      expect(r('What is this song?'), ChatIntent.nowPlaying);
      expect(r('who is the composer?'), ChatIntent.composer);
      expect(r('More like this'), ChatIntent.moreLikeThis);
      expect(r('Surprise me'), ChatIntent.flow);
      expect(r('my weekly mix'), ChatIntent.weekly);
      expect(r('something new'), ChatIntent.discover);
      expect(r('translate this song'), ChatIntent.translate);
      expect(r('recognise this song'), ChatIntent.recognize);
      expect(r('never recommend this artist'), ChatIntent.neverArtist);
      expect(r('never recommend this song'), ChatIntent.neverSong);
      expect(r('calm Tamil melodies'), ChatIntent.mix);
    });

    test('"more like this" asks about the current song', () {
      final song = Song(id: 's', title: 'Thaniye', artist: 'Anirudh', album: '', coverArt: '', duration: 1, track: 1, year: 0);
      expect(mixQuery('More like this', song), 'songs like Thaniye by Anirudh');
      expect(mixQuery('More like this', null), 'something I like');
      expect(mixQuery('rainy night drive', song), 'rainy night drive');
    });

    test('suggestions follow the song and the hour', () {
      final song = Song(
        id: 's', title: 'Thaniye', artist: 'Anirudh Ravichander, X', album: '', coverArt: '',
        duration: 1, track: 1, year: 0, composer: 'Anirudh',
      );
      final day = suggestChips(current: song, now: DateTime(2026, 1, 1, 14));
      expect(day.map((c) => c.label), containsAll(['More like this', 'What is this song?', 'Who is the composer?', 'Focus music']));
      expect(day.any((c) => c.label == 'More from Anirudh Ravichander'), isTrue);
      expect(day.length, lessThanOrEqualTo(6));
      final night = suggestChips(current: null, now: DateTime(2026, 1, 1, 23));
      expect(night.first.label, 'Something calm for the night');
      expect(night.any((c) => c.label == 'More like this'), isFalse, reason: 'nothing playing, nothing to be like');
    });
  });

  group('painter', () {
    for (final pose in MicroduckPose.values) {
      test('${pose.name} paints at several times and sizes without throwing', () {
        for (final t in [0.0, 0.07, 1.3, 3.55, 99.9]) {
          final painter = MicroduckPainter(
            pose: pose,
            time: ValueNotifier(t),
            input: MicroduckInput()..tapAt = t - 0.3,
            skin: t > 1 ? MicroduckSkin.grey : MicroduckSkin.white,
            bpm: 120,
          );
          for (final size in [const Size(12, 12), const Size(28, 28), const Size(96, 72), Size.zero]) {
            final recorder = PictureRecorder();
            expect(() => painter.paint(Canvas(recorder), size), returnsNormally);
            recorder.endRecording().dispose();
          }
        }
      });
    }
  });

  group('widget', () {
    testWidgets('renders every pose, and stays still under reduced motion', (tester) async {
      for (final reduced in [false, true]) {
        for (final pose in MicroduckPose.values) {
          await tester.pumpWidget(MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Microduck(pose: pose, interactive: true),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.hasRunningAnimations, !reduced);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('settings persistence', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hive_microduck');
      Hive.init(dir.path);
      HiveBoxes.auth = await Hive.openBox('auth');
      HiveBoxes.session = await Hive.openBox('session');
      HiveBoxes.prefs = await Hive.openBox('prefs');
      HiveBoxes.audio = await Hive.openBox('audio');
    });

    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('defaults: on, named Microduck', () {
      final s = SettingsNotifier().state;
      expect(s.microduckEnabled, isTrue);
      expect(s.microduckName, 'Microduck');
    });

    test('toggle and name survive a restart', () async {
      final n = SettingsNotifier();
      await n.setMicroduckEnabled(false);
      await n.setMicroduckName('  Quackers ');
      await n.setMicroduckSkin(MicroduckSkin.lilac);
      final again = SettingsNotifier().state;
      expect(again.microduckSkin, MicroduckSkin.lilac);
      expect(again.microduckEnabled, isFalse);
      expect(again.microduckName, 'Quackers');
      await n.setMicroduckName('');
      expect(SettingsNotifier().state.microduckName, 'Microduck');
    });

    test('cachedBpm reads the tempo cache', () async {
      expect(cachedBpm('s1'), isNull);
      await HiveBoxes.audio.put('bpm_s1', 128);
      expect(cachedBpm('s1'), 128);
    });

    testWidgets('strip is empty when switched off', (tester) async {
      // Hive writes are real I/O; they never finish inside the fake clock.
      await tester.runAsync(() => HiveBoxes.prefs.put(HiveBoxes.kMicroduckEnabled, false));
      await tester.pumpWidget(const ProviderScope(
        child: Directionality(textDirection: TextDirection.ltr, child: MicroduckStrip(progress: 0.5)),
      ));
      expect(find.byType(Microduck), findsNothing);
    });
  });
}
