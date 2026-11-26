import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/features/equalizer/data/eq_engine.dart';
import 'package:navivibe/features/equalizer/logic/eq_model.dart';
import 'package:navivibe/features/equalizer/logic/equalizer_service.dart';
import 'package:navivibe/features/equalizer/logic/mpv_filter.dart';
import 'package:navivibe/features/equalizer/ui/eq_curve.dart';
import 'package:navivibe/features/equalizer/ui/equalizer_screen.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/player_volume.dart';
import 'package:navivibe/services/playback_tuning.dart';

class _FakeEngine extends EqEngine {
  final calls = <List<double>?>[];
  bool fail = false;

  @override
  Future<void> apply(List<double>? gains) async {
    if (fail) throw StateError('not ready');
    calls.add(gains == null ? null : [...gains]);
  }
}

EqualizerService _service(_FakeEngine? engine, [Map<String, Object?>? store]) {
  final s = store ?? <String, Object?>{};
  return EqualizerService(engine, read: (k) => s[k], write: (k, v) async => s[k] = v)..load();
}

Song _song({double? gain, double? peak}) => Song(
      id: 's',
      title: 't',
      artist: 'a',
      album: 'b',
      coverArt: 's',
      duration: 100,
      track: 1,
      year: 2020,
      trackGain: gain,
      trackPeak: peak,
    );

void main() {
  group('curve', () {
    test('passes through every band and never overshoots', () {
      const gains = [12.0, -12.0, 12.0, 0.0, 6.0, -3.0];
      for (var i = 0; i < gains.length; i++) {
        expect(gainAtHz(gains, kEqFrequencies[i]), closeTo(gains[i], 1e-9));
      }
      for (var hz = 20.0; hz < 20000; hz *= 1.03) {
        expect(gainAtHz(gains, hz).abs(), lessThanOrEqualTo(12 + 1e-9));
      }
    });

    test('is flat past the end bands', () {
      const gains = [5.0, 0.0, 0.0, 0.0, 0.0, -4.0];
      expect(gainAtHz(gains, 25), 5);
      expect(gainAtHz(gains, 19000), -4);
    });

    test('slices rise in frequency and cover the audible range', () {
      final slices = eqSlices([6, 4, 1, 0, -2, -4]);
      expect(slices, hasLength(kEqSliceCount));
      for (var i = 1; i < slices.length; i++) {
        expect(slices[i].cutoffHz, greaterThan(slices[i - 1].cutoffHz));
      }
      expect(slices.last.cutoffHz, closeTo(20000, 1));
      expect(slices.first.gainDb, 6);
    });

    test('damaged preferences become flat', () {
      expect(sanitizeGains(null), flatGains());
      expect(sanitizeGains([1, 2, 3, 4, 5]), flatGains()); // old 5-band save
      expect(sanitizeGains([1, 2, 'x', 4, 5, 6]), flatGains());
      expect(sanitizeGains([99, -99, 0, 0, 0, 0]), [12, -12, 0, 0, 0, 0]);
    });

    test('headroom cancels the biggest boost only', () {
      expect(headroomDb([-3, 0, 7, 2]), -7);
      expect(headroomDb([-3, -8]), 0);
    });
  });

  group('desktop filter', () {
    test('solved bank hits the six targets', () {
      const target = [8.0, 4.0, -3.0, 2.0, -6.0, 5.0];
      final solved = solveFilterGains(target);
      for (var i = 0; i < target.length; i++) {
        expect(bankResponseDb(solved, kEqFrequencies[i]), closeTo(target[i], 0.15), reason: '${kEqFrequencies[i]} Hz');
      }
    });

    test('starts with the mpv format conversion the Windows build needs', () {
      final eq = mpvEqFor([6, 0, 0, 0, 0, 0]);
      expect(eq.filter, startsWith('format=format=floatp,lavfi=['));
      expect('equalizer='.allMatches(eq.filter), hasLength(6));
    });

    test('headroom covers the loudest point of the bank', () {
      const target = [12.0, 12.0, 12.0, 12.0, 12.0, 12.0];
      final eq = mpvEqFor(target);
      final peak = bankPeakDb(solveFilterGains(target));
      expect(eq.headroom, closeTo(math.pow(10, -peak / 20), 1e-9));
      expect(peak, greaterThanOrEqualTo(12 - 0.2));
    });

    test('flat is no filter at all', () {
      expect(mpvEqFor(flatGains()).filter, '');
      expect(mpvEqFor(flatGains()).headroom, 1);
    });
  });

  group('service', () {
    test('never touches the engine while off, or on and flat', () async {
      final engine = _FakeEngine();
      final eq = _service(engine);
      await eq.sync();
      eq.setBand(0, 6); // curve changes while off
      await eq.sync();
      eq.setBand(0, 0);
      await eq.setEnabled(true); // on, flat
      expect(engine.calls, isEmpty);
      expect(eq.isActive, isFalse);
    });

    test('applies when active and removes the effect when switched off', () async {
      final engine = _FakeEngine();
      final eq = _service(engine);
      await eq.setEnabled(true);
      eq.setBand(1, 4);
      await eq.sync();
      expect(engine.calls.last, [0, 4, 0, 0, 0, 0]);
      await eq.setEnabled(false);
      expect(engine.calls.last, isNull);
    });

    test('a refused apply is retried by the next sync', () async {
      final engine = _FakeEngine()..fail = true;
      final eq = _service(engine);
      eq.setBand(0, 3);
      await eq.setEnabled(true);
      expect(engine.calls, isEmpty);
      engine.fail = false;
      await eq.sync();
      expect(engine.calls.single, [3, 0, 0, 0, 0, 0]);
    });

    test('keeps the curve, the switch and saved presets across restarts', () async {
      final store = <String, Object?>{};
      final eq = _service(_FakeEngine(), store);
      await eq.setEnabled(true);
      eq.setBand(2, -5);
      await eq.commitCurve();
      expect(eq.canSave, isTrue);
      expect(await eq.savePreset('  Car  '), isTrue);

      final again = _service(_FakeEngine(), store);
      expect(again.enabled, isTrue);
      expect(again.gains[2], -5);
      expect(again.preset?.name, 'Car');
      expect(again.canDelete, isTrue);
      expect(store[HiveBoxes.kEqualizerPresets], isA<List<Object?>>());

      await again.deletePreset();
      expect(again.customPresets, isEmpty);
      expect(again.gains[2], -5, reason: 'deleting a preset keeps the sound');
    });

    test('built-in presets cannot be overwritten or deleted', () async {
      final eq = _service(_FakeEngine());
      await eq.selectPreset(kBuiltInPresets[1]);
      expect(eq.canDelete, isFalse);
      expect(await eq.savePreset('flat'), isFalse);
      expect(await eq.savePreset('  '), isFalse);
      await eq.reset();
      expect(eq.preset?.name, 'Flat');
    });

    test('unsupported platforms are never active', () async {
      final eq = _service(null);
      await eq.setEnabled(true);
      eq.setBand(0, 6);
      expect(eq.isSupported, isFalse);
      expect(eq.isActive, isFalse);
    });
  });

  group('volume and loudness', () {
    test('a cubic player is given the cube root of the amplitude', () {
      // mpv at 0.5 plays at 0.125: so 0.125 of amplitude needs 0.5.
      expect(effectiveVolume(1, 0.125, cubic: true), closeTo(0.5, 1e-9));
      expect(effectiveVolume(1, 0.125, cubic: false), 0.125);
      expect(effectiveVolume(0.8, 1, cubic: true), closeTo(0.8, 1e-9));
    });

    test('loudness level raises the target but a peak still caps it', () {
      final v = replayGainVolume(_song(gain: -10), ReplayGainMode.track, preampDb: 4);
      expect(v, closeTo(math.pow(10, -6 / 20), 1e-9));
      // -2 dB + 4 would be 1.26; a 0.95 peak allows 1.05, capped at full.
      expect(replayGainVolume(_song(gain: -2, peak: 0.95), ReplayGainMode.track, preampDb: 4), 1.0);
      expect(replayGainVolume(_song(gain: -2, peak: 1.25), ReplayGainMode.track, preampDb: 4), closeTo(0.8, 1e-9));
    });

    test('untagged songs play at the stand-in level, and off stays at 1.0', () {
      final v = replayGainVolume(_song(), ReplayGainMode.track, preampDb: 4, untaggedDb: kUntaggedGainDb);
      expect(v, closeTo(math.pow(10, (kUntaggedGainDb + 4) / 20), 1e-9));
      expect(replayGainVolume(_song(), ReplayGainMode.off, preampDb: 7, untaggedDb: -8), 1.0);
    });
  });

  group('screen', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('dragging a band up boosts it, and Reset flattens', (tester) async {
      final engine = _FakeEngine();
      final eq = _service(engine);
      await eq.setEnabled(true);
      await tester.pumpWidget(host(EqualizerPanel(equalizer: eq)));

      final curve = tester.getRect(find.byType(EqCurve));
      final plotLeft = curve.left + 52;
      final column = (curve.width - 52) / 6;
      final start = Offset(plotLeft + column * 0.5, curve.top + 120);
      await tester.dragFrom(start, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(eq.gains.first, 12);
      expect(eq.gains.skip(1), everyElement(0));
      expect(engine.calls.last, [12, 0, 0, 0, 0, 0]);
      expect(find.text('Save preset'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(eq.gains, flatGains());
      expect(engine.calls.last, isNull);
      expect(find.text('Flat'), findsOneWidget);
    });

    testWidgets('switched off, the curve does not move', (tester) async {
      final eq = _service(_FakeEngine());
      await tester.pumpWidget(host(EqualizerPanel(equalizer: eq)));
      await tester.dragFrom(tester.getCenter(find.byType(EqCurve)), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(eq.gains, flatGains());
    });

    testWidgets('arrow keys change the focused band', (tester) async {
      final eq = _service(_FakeEngine());
      await eq.setEnabled(true);
      await tester.pumpWidget(host(EqualizerPanel(equalizer: eq)));
      final first = tester.widgetList<Focus>(find.descendant(of: find.byType(EqCurve), matching: find.byType(Focus)))
          .firstWhere((f) => f.focusNode?.debugLabel == 'eq-60Hz');
      first.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(eq.gains, [1, -1, 0, 0, 0, 0]);
    });
  });
}
