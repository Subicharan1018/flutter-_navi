import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/keyboard_shortcuts.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/services/voice_input.dart';
import 'package:navivibe/widgets/ui/voice_search_button.dart';

Widget _app(Widget child) => ProviderScope(
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

/// Three focus stops in a row.
Widget _row({required List<String> log, bool withLongPress = false}) => Row(
      children: [
        for (final name in ['a', 'b', 'c'])
          SizedBox(
            width: 80,
            height: 80,
            child: NaviFocusRing(
              autofocus: name == 'a',
              onTap: () => log.add('tap $name'),
              onLongPress: withLongPress ? () => log.add('long $name') : null,
              child: Center(child: Text(name)),
            ),
          ),
      ],
    );

bool _ringShown(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .any((d) => d.position == DecorationPosition.foreground && (d.decoration as BoxDecoration).border != null);

FocusNode _node(WidgetTester tester, String text) => Focus.of(tester.element(find.text(text)));

void main() {
  testWidgets('D-pad right/left walks the row in order', (tester) async {
    await tester.pumpWidget(_app(_row(log: [])));
    await tester.pump();

    expect(_node(tester, 'a').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_node(tester, 'b').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_node(tester, 'c').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_node(tester, 'b').hasPrimaryFocus, isTrue);
  });

  testWidgets('the ring shows for key navigation and not for touch', (tester) async {
    await tester.pumpWidget(_app(_row(log: [])));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_ringShown(tester), isTrue);

    // A touch switches the highlight mode back off.
    await tester.tap(find.text('c'));
    await tester.pump();
    expect(_ringShown(tester), isFalse);
  });

  testWidgets('Select and Enter activate the focused item', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row(log: log)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(log, ['tap a', 'tap b']);
  });

  testWidgets('holding Select runs the long-press action instead of a tap', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row(log: log, withLongPress: true)));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(kRemoteLongPress + const Duration(milliseconds: 50));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(log, ['long a']);

    log.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(log, ['tap a']);
  });

  testWidgets('the Menu key opens the context action', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row(log: log, withLongPress: true)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(log, ['long a']);
  });

  testWidgets('NaviFocusable: right-click runs the context action', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(Center(
      child: NaviFocusable(
        onTap: () => log.add('tap'),
        onLongPress: () => log.add('menu'),
        child: const SizedBox(width: 100, height: 40, child: Text('row')),
      ),
    )));
    await tester.tap(find.text('row'), buttons: kSecondaryButton);
    await tester.pump();
    expect(log, ['menu']);
  });

  testWidgets('focus returns to the item that opened a page', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Row(
                children: [
                  for (final name in ['a', 'b', 'c'])
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: NaviFocusRing(
                        autofocus: name == 'a',
                        onTap: name == 'b'
                            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    body: NaviFocusRing(autofocus: true, onTap: () {}, child: const Text('detail')),
                                  ),
                                ))
                            : () {},
                        child: Center(child: Text(name)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // → b
    await tester.sendKeyEvent(LogicalKeyboardKey.select); // opens the page
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(_node(tester, 'b').hasPrimaryFocus, isTrue);
  });

  group('key map', () {
    Future<Map<ShortcutActivator, VoidCallback>> bindings(WidgetTester tester, {required bool desktop}) async {
      late Map<ShortcutActivator, VoidCallback> map;
      await tester.pumpWidget(ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          map = buildNaviBindings(ref, null, desktop: desktop);
          return const SizedBox();
        }),
      ));
      return map;
    }

    bool has(Map<ShortcutActivator, VoidCallback> m, LogicalKeyboardKey k) =>
        m.keys.whereType<SingleActivator>().any((a) => a.trigger == k && !a.control && !a.alt);

    testWidgets('a TV keeps arrows for the D-pad but maps the media keys', (tester) async {
      final m = await bindings(tester, desktop: false);
      expect(has(m, LogicalKeyboardKey.mediaPlayPause), isTrue);
      expect(has(m, LogicalKeyboardKey.mediaRewind), isTrue);
      expect(has(m, LogicalKeyboardKey.mediaFastForward), isTrue);
      expect(has(m, LogicalKeyboardKey.speechInputToggle), isTrue);
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.space,
      ]) {
        expect(has(m, k), isFalse, reason: '$k must stay with focus traversal');
      }
    });

    testWidgets('desktop adds space and arrows for seek and volume', (tester) async {
      final m = await bindings(tester, desktop: true);
      for (final k in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.mediaTrackNext,
      ]) {
        expect(has(m, k), isTrue, reason: '$k');
      }
    });

    testWidgets('with shell commands the desktop gets Ctrl+F, /, Ctrl+1..5, Esc; the voice key only opens Search', (tester) async {
      late Map<ShortcutActivator, VoidCallback> map;
      final calls = <String>[];
      await tester.pumpWidget(ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          map = buildNaviBindings(
            ref,
            ShellCommands(
              openSearch: () => calls.add('open'),
              focusSearch: () => calls.add('search'),
              openSettings: () => calls.add('settings'),
              selectTab: (i) => calls.add('tab$i'),
              goBack: () {
                calls.add('back');
                return true;
              },
            ),
            desktop: true,
          );
          return const SizedBox();
        }),
      ));
      map[const SingleActivator(LogicalKeyboardKey.keyF, control: true)]!();
      map.entries.firstWhere((e) => e.key is SingleActivator && (e.key as SingleActivator).trigger == LogicalKeyboardKey.digit4 && (e.key as SingleActivator).control).value();
      map[const SingleActivator(LogicalKeyboardKey.escape)]!();
      map[const SingleActivator(LogicalKeyboardKey.slash)]!();
      map[const SingleActivator(LogicalKeyboardKey.speechInputToggle)]!();
      expect(calls, ['search', 'tab3', 'back', 'search', 'open']);
    });
  });

  group('voice search button', () {
    late _FakeVoice voice;
    final original = VoiceInput.engine;
    setUp(() => VoiceInput.engine = voice = _FakeVoice());
    tearDown(() => VoiceInput.engine = original);

    testWidgets('dictation lands in the field and submits the final words', (tester) async {
      final controller = TextEditingController();
      String? submitted;
      await tester.pumpWidget(_app(VoiceSearchButton(controller: controller, onSubmitted: (q) => submitted = q)));
      await tester.tap(find.byType(VoiceSearchButton));
      await tester.pump();

      voice.onText!('hello wor', false);
      expect(controller.text, 'hello wor');
      voice.onText!('hello world', true);
      voice.onDone!(null);
      await tester.pump();
      expect(controller.text, 'hello world');
      expect(submitted, 'hello world');
      // Let the pulse animation's controller wind down before teardown.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hidden where there is no speech service to ask', (tester) async {
      voice.supported = false;
      await tester.pumpWidget(_app(VoiceSearchButton(controller: TextEditingController())));
      expect(find.byType(CupertinoClickable), findsNothing);
    });

    testWidgets('says so plainly when the device has no recognizer', (tester) async {
      voice.startResult = false;
      voice.failure = VoiceFailure.unavailable;
      await tester.pumpWidget(_app(VoiceSearchButton(controller: TextEditingController())));
      await tester.tap(find.byType(VoiceSearchButton));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('isn’t available'), findsOneWidget);
    });

    testWidgets("the remote's voice key starts listening", (tester) async {
      await tester.pumpWidget(_app(
        VoiceSearchButton(controller: TextEditingController(), listenForVoiceKey: true),
      ));
      voiceKeyPresses.value++;
      await tester.pump();
      expect(voice.starts, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _FakeVoice implements VoiceEngine {
  bool supported = true;
  bool startResult = true;
  VoiceFailure? failure;
  int starts = 0;
  void Function(String, bool)? onText;
  void Function(VoiceFailure?)? onDone;
  bool _listening = false;

  @override
  bool get supportedPlatform => supported;

  @override
  bool get listening => _listening;

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceFailure? failure) onDone,
  }) async {
    starts++;
    this.onText = onText;
    this.onDone = onDone;
    _listening = startResult;
    if (!startResult) onDone(failure);
    return startResult;
  }

  @override
  Future<void> stop() async => _listening = false;
}
