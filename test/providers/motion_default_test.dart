import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/utils/platform_utils.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_motion_default');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });
  tearDownAll(() async {
    await Hive.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  setUp(() async {
    await HiveBoxes.prefs.delete(HiveBoxes.kMotionLevel);
    PlatformUtils.debugTvOverride = null;
    PlatformUtils.debugLowRamOverride = null;
  });
  tearDown(() {
    PlatformUtils.debugTvOverride = null;
    PlatformUtils.debugLowRamOverride = null;
  });

  MotionLevel loaded() {
    final n = SettingsNotifier();
    addTearDown(n.dispose);
    return n.state.motionLevel;
  }

  test('a phone with enough memory starts on Full', () {
    PlatformUtils.debugTvOverride = false;
    PlatformUtils.debugLowRamOverride = false;
    expect(loaded(), MotionLevel.full);
  });

  test('a TV or a low-RAM phone that never chose starts on Reduced', () {
    PlatformUtils.debugTvOverride = true;
    expect(loaded(), MotionLevel.reduced);
    PlatformUtils.debugTvOverride = false;
    PlatformUtils.debugLowRamOverride = true;
    expect(loaded(), MotionLevel.reduced);
  });

  test('a choice already made is never overridden', () async {
    PlatformUtils.debugTvOverride = true;
    await HiveBoxes.prefs.put(HiveBoxes.kMotionLevel, MotionLevel.full.name);
    expect(loaded(), MotionLevel.full);
  });
}
