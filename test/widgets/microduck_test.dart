import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' show PictureRecorder;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/widgets/mascot/microduck.dart';
import 'package:navivibe/widgets/mascot/microduck_painter.dart';
import 'package:navivibe/widgets/mascot/microduck_pose.dart';
import 'package:navivibe/widgets/mascot/microduck_strip.dart';

void main() {
  group('pose selection', () {
    final noon = DateTime(2026, 1, 1, 12);
    final night = DateTime(2026, 1, 1, 2, 30);

    test('plays: runs; paused: stands', () {
      expect(resolveMicroduckPose(playing: true, now: noon), MicroduckPose.run);
      expect(resolveMicroduckPose(playing: false, now: noon), MicroduckPose.idle);
    });

    test('sleeps from 00:00 to 04:59, wakes at 05:00', () {
      expect(isMicroduckNight(DateTime(2026, 1, 1, 0)), isTrue);
      expect(isMicroduckNight(DateTime(2026, 1, 1, 4, 59)), isTrue);
      expect(isMicroduckNight(DateTime(2026, 1, 1, 5)), isFalse);
      expect(resolveMicroduckPose(playing: true, now: night), MicroduckPose.sleep);
      expect(resolveMicroduckPose(playing: true, now: night, sleepsAtNight: false), MicroduckPose.run);
    });

    test('dances only when allowed and the tempo is known', () {
      expect(resolveMicroduckPose(playing: true, now: noon, allowDance: true, bpm: 120), MicroduckPose.dance);
      expect(resolveMicroduckPose(playing: true, now: noon, allowDance: true), MicroduckPose.run);
      expect(resolveMicroduckPose(playing: true, now: noon, bpm: 120), MicroduckPose.run);
      expect(resolveMicroduckPose(playing: false, now: noon, allowDance: true, bpm: 120), MicroduckPose.idle);
    });

    test('reduced motion gets a still pose', () {
      expect(resolveMicroduckPose(playing: true, now: noon, reducedMotion: true, allowDance: true, bpm: 120),
          MicroduckPose.idle);
      expect(resolveMicroduckPose(playing: true, now: night, reducedMotion: true), MicroduckPose.sleep);
    });

    test('tempo folds into a hoppable range', () {
      expect(danceBpm(null), isNull);
      expect(danceBpm(0), isNull);
      expect(danceBpm(120), 120);
      expect(danceBpm(180), 90);
      expect(danceBpm(50), 100);
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

  group('painter', () {
    for (final pose in MicroduckPose.values) {
      test('${pose.name} paints at several times and sizes without throwing', () {
        for (final t in [0.0, 0.07, 1.3, 3.55, 99.9]) {
          final painter = MicroduckPainter(
            pose: pose,
            time: ValueNotifier(t),
            color: Colors.white,
            beat: 0.5,
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
              child: Microduck(pose: pose, color: Colors.white),
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
      final again = SettingsNotifier().state;
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
