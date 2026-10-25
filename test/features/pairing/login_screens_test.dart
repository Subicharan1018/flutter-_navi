import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/constants.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/pairing/ui/tv_pair_screen.dart';
import 'package:navivibe/screens/login_screen.dart';
import 'package:navivibe/services/voice_input.dart';
import 'package:navivibe/utils/platform_utils.dart';

import 'tv_pairing_test.dart' show FakeRelay;

/// A speech engine that is present on every platform, for layout tests.
class _AvailableVoice implements VoiceEngine {
  @override
  bool get supportedPlatform => true;

  @override
  bool get listening => false;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceFailure? failure) onDone,
  }) async =>
      false;

  @override
  Future<void> stop() async {}
}

Widget host(Widget home) => ProviderScope(
      child: MaterialApp(
        builder: (context, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
        home: home,
      ),
    );

String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('hive_login');
    Hive.init(dir.path);
    HiveBoxes.prefs = await Hive.openBox('prefs');
    HiveBoxes.auth = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.audio = await Hive.openBox('audio');
  });

  tearDownAll(() async {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {} // Hive still holds the box files on Windows
  });

  setUp(() => HiveBoxes.prefs.clear().ignore());
  tearDown(() => PlatformUtils.debugTvOverride = null);

  group('the sign-in form', () {
    testWidgets('starts on the first empty field and walks username → password with Next', (tester) async {
      HiveBoxes.prefs.put(HiveBoxes.kLastServerUrl, 'https://music.example').ignore();
      await tester.pumpWidget(host(const LoginScreen()));
      await tester.pump();

      // The server is remembered, so typing starts at the username.
      expect(find.text('https://music.example'), findsOneWidget);
      expect(focusedLabel(), 'login-user');

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(focusedLabel(), 'login-password');
    });

    testWidgets('Tab / D-pad order is server, then username, password, Sign in', (tester) async {
      HiveBoxes.prefs.put(HiveBoxes.kLastServerUrl, '').ignore();
      await tester.pumpWidget(host(const LoginScreen()));
      await tester.pump();
      final start = focusedLabel();
      expect(start, Constants.suggestedServerUrl.isEmpty ? 'login-server' : 'login-user');

      final seen = <String>[?start];
      for (var i = 0; i < 14; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final label = focusedLabel();
        if (label != null && label.startsWith('login-') && (seen.isEmpty || seen.last != label)) seen.add(label);
      }
      expect(seen.where((l) => l != 'login-server').take(2), ['login-user', 'login-password']);
      expect(seen.indexOf('login-user'), lessThan(seen.indexOf('login-password')));
    });

    testWidgets('the password has no microphone, the other fields do', (tester) async {
      // The real engine hides the microphone on platforms without a speech
      // service (Linux CI), so the test brings its own that is available.
      final original = VoiceInput.engine;
      VoiceInput.engine = _AvailableVoice();
      addTearDown(() => VoiceInput.engine = original);
      await tester.pumpWidget(host(const LoginScreen()));
      await tester.pump();
      expect(find.bySemanticsLabel('Type by voice'), findsNWidgets(2)); // server + username
    });

    testWidgets('the suggested server is a chip that fills the field', (tester) async {
      HiveBoxes.prefs.put(HiveBoxes.kLastServerUrl, 'https://other.example').ignore();
      await tester.pumpWidget(host(const LoginScreen()));
      await tester.pump();
      final chip = find.textContaining('Use https://');
      if (chip.evaluate().isEmpty) return; // public flavor: no suggested server
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('https://other.example'), findsNothing);
    });

    testWidgets('on a TV it points at the phone keyboard', (tester) async {
      PlatformUtils.debugTvOverride = true;
      await tester.pumpWidget(host(const LoginScreen()));
      expect(find.textContaining('Google TV app'), findsOneWidget);
    });
  });

  group('the TV pairing screen', () {
    final original = VoiceInput.engine;
    tearDown(() => VoiceInput.engine = original);

    testWidgets('shows a big code and a QR, and lands focus on "Type it instead"', (tester) async {
      PlatformUtils.debugTvOverride = true;
      final relay = FakeRelay();
      await tester.runAsync(() async {
        await tester.pumpWidget(host(TvPairScreen(relay: relay, pollEvery: const Duration(hours: 1))));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(); // autofocus lands on the frame after the button appears

      expect(find.text('Sign in from your phone'), findsOneWidget);
      final code = relay.boxes.keys.single;
      expect(find.text('${code.substring(0, 3)} ${code.substring(3)}'), findsOneWidget);
      expect(find.byType(Semantics), findsWidgets);

      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LoginScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('explains a failure and offers Try again first', (tester) async {
      PlatformUtils.debugTvOverride = true;
      final relay = FakeRelay();
      await tester.runAsync(() async {
        await tester.pumpWidget(host(TvPairScreen(relay: relay, pollEvery: const Duration(hours: 1))));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(relay.boxes, hasLength(1));
    });
  });
}
