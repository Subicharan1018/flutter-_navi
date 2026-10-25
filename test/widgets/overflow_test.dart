import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/pairing/ui/sign_in_another_device_screen.dart';
import 'package:navivibe/features/pairing/ui/tv_pair_screen.dart';
import 'package:navivibe/screens/login_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/tv_frame.dart';
import 'package:navivibe/widgets/shell/tv_shell.dart';
import 'package:navivibe/widgets/shell/app_tab.dart';
import 'package:navivibe/widgets/ui/horizontal_shelf.dart';
import 'package:navivibe/widgets/ui/media.dart';

import '../features/pairing/tv_pairing_test.dart' show FakeRelay;

/// Every size NaviVibe is meant to fit: phones at three text scales, a Windows
/// window from its minimum to a 1920×1200 maximised one, and a TV.
const _phones = [Size(360, 800), Size(412, 915)];
const _windows = [Size(800, 600), Size(1024, 700), Size(1366, 768), Size(1920, 1200)];
const _scales = [1.0, 1.3, 1.6];

/// Fails on a RenderFlex overflow or any other framework error while [build]
/// is on screen at [size] (logical px) with text [scale].
Future<void> _expectFits(
  WidgetTester tester,
  String what,
  Widget Function() build,
  Size size, {
  double scale = 1.0,
  double dpr = 1.0,
  bool tv = false,
}) async {
  PlatformUtils.debugTvOverride = tv;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = size * dpr;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    PlatformUtils.debugTvOverride = null;
  });
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      builder: (context, child) => ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: TvFrame(child: child!),
        ),
      ),
      home: build(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = previous;
  final overflows = errors.where((e) => e.exceptionAsString().contains('overflowed')).toList();
  expect(
    errors.map((e) => e.exceptionAsString().split('\n').first).toList(),
    isEmpty,
    reason: '$what at ${size.width.toInt()}x${size.height.toInt()} text ×$scale '
        '(${overflows.length} overflow${overflows.length == 1 ? '' : 's'})',
  );
}

Widget _shelf() => Scaffold(
      body: ListView(children: [
        MediaShelf(
          title: 'New in Your Library',
          itemCount: 12,
          itemBuilder: (context, i) => MediaCard(
            title: 'A very long album title that must be ellipsised, not clipped mid-word $i',
            subtitle: 'An artist with a very long name, Another Artist · New · Worldwide',
            size: 150,
            onTap: () {},
          ),
        ),
      ]),
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_overflow');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final size in [..._phones, ..._windows]) {
    for (final scale in _scales) {
      testWidgets('sign-in form fits ${size.width.toInt()}x${size.height.toInt()} ×$scale', (tester) async {
        await _expectFits(tester, 'LoginScreen', () => const LoginScreen(), size, scale: scale);
      });
      testWidgets('shelf captions ellipsise at ${size.width.toInt()}x${size.height.toInt()} ×$scale', (tester) async {
        await _expectFits(tester, 'MediaShelf', _shelf, size, scale: scale);
      });
    }
  }

  testWidgets('pairing screens fit a TV canvas at 960x540@2 and 1280x720@1.5', (tester) async {
    for (final s in const [(Size(960, 540), 2.0), (Size(1280, 720), 1.5), (Size(1920, 1080), 1.0)]) {
      await _expectFits(
        tester,
        'TvPairScreen',
        () => TvPairScreen(relay: FakeRelay(), pollEvery: const Duration(hours: 1)),
        s.$1,
        dpr: s.$2,
        tv: true,
      );
    }
  });

  testWidgets('the sign-in form fits a TV canvas (two-pane layout)', (tester) async {
    for (final s in const [(Size(960, 540), 2.0), (Size(1280, 720), 1.5)]) {
      await _expectFits(tester, 'LoginScreen on TV', () => const LoginScreen(), s.$1, dpr: s.$2, tv: true);
    }
  });

  testWidgets('"Sign in another device" fits phone sizes and large text', (tester) async {
    for (final size in _phones) {
      for (final scale in _scales) {
        await _expectFits(
          tester,
          'SignInAnotherDeviceScreen',
          () => SignInAnotherDeviceScreen(relay: FakeRelay()),
          size,
          scale: scale,
        );
      }
    }
  });

  testWidgets('the TV rail fits at every TV density', (tester) async {
    for (final s in const [(Size(960, 540), 2.0), (Size(1280, 720), 1.5), (Size(1366, 768), 1.405)]) {
      await _expectFits(
        tester,
        'TvRail',
        () => Scaffold(body: Row(children: [TvRail(tab: AppTab.home, onSelect: (_) {}), const Expanded(child: SizedBox())])),
        s.$1,
        dpr: s.$2,
        tv: true,
      );
    }
  });

  testWidgets('a horizontal shelf fades its cut edge and pages with the mouse', (tester) async {
    PlatformUtils.debugTvOverride = false;
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: Scaffold(
          body: HorizontalShelf(
            height: 120,
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(width: 100, child: Text('card $i')),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ShaderMask), findsWidgets, reason: 'the shelf masks its edges');
    final before = tester.getTopLeft(find.text('card 4')).dx;
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('card 4')).dx, lessThan(before), reason: 'it scrolls');
  });
}
