import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/flow/logic/flow_controller.dart';
import 'package:navivibe/features/flow/ui/flow_pill.dart';
import 'package:navivibe/features/flow/ui/flow_section.dart';
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/utils/platform_utils.dart';

/// Flow without a server or a player: records what the UI asked it to do.
class FakeFlow extends FlowController {
  final FlowState initial;
  final List<String> calls;
  FakeFlow(this.initial, this.calls);

  @override
  FlowState build() => initial;
  @override
  Future<bool> start() async {
    calls.add('start');
    return true;
  }

  @override
  Future<bool> retry() async {
    calls.add('retry');
    return true;
  }

  @override
  void stop() => calls.add('stop');
  @override
  Future<void> selectMood(String? mood) async {
    calls.add('mood:$mood');
    state = state.copyWith(mood: mood);
  }
}

const moods = [FlowMood('chill', 40), FlowMood('happy', 30)];

Widget flowApp(Widget child, FlowState state, List<String> calls, {Future<List<FlowMood>> Function()? moodsLoader}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: <Override>[
      flowProvider.overrideWith(() => FakeFlow(state, calls)),
      flowMoodsProvider.overrideWith((ref) => (moodsLoader ?? () async => moods)()),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  Future<void> size(WidgetTester tester, Size s, {bool desktop = false}) async {
    PlatformUtils.debugDesktopOverride = desktop;
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('phone', () {
    testWidgets('a picked mood is named before Flow starts', (tester) async {
      await size(tester, const Size(390, 844));
      final calls = <String>[];
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), calls));
      await tester.pumpAndSettle();
      expect(find.text('Starts with any mood.'), findsOneWidget);
      await tester.tap(find.text('Chill'));
      await tester.pumpAndSettle();
      expect(calls, ['mood:chill']);
      expect(find.text('Starts with Chill.'), findsOneWidget);
    });

    testWidgets('while Flow plays, the mood line says switching swaps what is to come', (tester) async {
      await size(tester, const Size(390, 844));
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(active: true, mood: 'happy'), []));
      await tester.pumpAndSettle();
      expect(find.text('Switching mood swaps the songs still to come.'), findsOneWidget);
      expect(find.text('Playing Happy songs, picked as you go.'), findsOneWidget);
      expect(find.text('Stop Flow'), findsOneWidget);
    });

    testWidgets('an empty mood list says why instead of vanishing', (tester) async {
      await size(tester, const Size(390, 844));
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), [], moodsLoader: () async => const []));
      await tester.pumpAndSettle();
      expect(find.text('Mood choices show up once your songs have moods.'), findsOneWidget);
    });

    testWidgets('moods that fail to load offer Retry', (tester) async {
      await size(tester, const Size(390, 844));
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), [], moodsLoader: () async => throw 'x'));
      await tester.pumpAndSettle();
      expect(find.text('Moods didn’t load.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('an error shows once, inline, with Retry, and no toast', (tester) async {
      await size(tester, const Size(390, 844));
      final calls = <String>[];
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(error: 'Flow couldn’t load songs. Try again.'), calls));
      await tester.pumpAndSettle();
      expect(find.text('Flow couldn’t load songs. Try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, ['retry']);
      await tester.tap(find.text('Start Flow'));
      await tester.pumpAndSettle();
      expect(calls, ['retry', 'start']);
      expect(find.text('Flow couldn’t load songs. Try again.'), findsOneWidget); // not duplicated by a toast
    });

    testWidgets('the blend strip is described while Flow is active', (tester) async {
      await size(tester, const Size(390, 844));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(flowApp(
        const FlowSection(),
        const FlowState(active: true, blend: FlowBlend(familiar: 6, fresh: 3, explore: 1)),
        [],
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Last batch: 6 familiar, 3 fresh, 1 in a new language'), findsOneWidget);
      expect(find.text('Familiar 6'), findsOneWidget);
      expect(find.text('Fresh 3'), findsOneWidget);
      expect(find.text('New language 1'), findsOneWidget);
      handle.dispose();
    });
  });

  group('pill', () {
    testWidgets('hidden unless Flow is active', (tester) async {
      await size(tester, const Size(390, 844));
      await tester.pumpWidget(flowApp(const FlowPill(), const FlowState(), []));
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('targets are at least 44 tall and a long mood shortens instead of overflowing', (tester) async {
      await size(tester, const Size(200, 400));
      final calls = <String>[];
      await tester.pumpWidget(flowApp(const FlowPill(), FlowState(active: true, mood: 'extraordinarily-long-mood-name' * 2), calls));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final targets = find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 44);
      expect(targets, findsNWidgets(2)); // the mood and Stop
      for (final e in targets.evaluate()) {
        expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.text('Stop'));
      expect(calls, ['stop']);
    });

    testWidgets('the badge for other surfaces shows only while active and names the mood', (tester) async {
      await size(tester, const Size(390, 844));
      await tester.pumpWidget(flowApp(const FlowActiveBadge(), const FlowState(active: true, mood: 'chill'), []));
      await tester.pumpAndSettle();
      expect(find.text('Flow · Chill'), findsOneWidget);
    });
  });

  group('Home mood chips (Windows)', () {
    for (final active in [false, true]) {
      testWidgets('the moods are in view ${active ? 'while Flow runs' : 'before it starts'}', (tester) async {
        await size(tester, const Size(1366, 768), desktop: true);
        final calls = <String>[];
        await tester.pumpWidget(flowApp(const FlowMoodChips(), FlowState(active: active), calls));
        await tester.pumpAndSettle();
        expect(find.text('Any mood'), findsOneWidget);
        await tester.tap(find.text('Chill'));
        await tester.pump();
        expect(calls, contains('mood:chill'));
      });
    }
  });

  group('Windows', () {
    testWidgets('one inline row: Start sits beside the words and does not stretch', (tester) async {
      await size(tester, const Size(1280, 800), desktop: true);
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), []));
      await tester.pumpAndSettle();
      final start = tester.getRect(find.text('Start Flow'));
      expect(tester.getSize(find.text('Start Flow')).width, lessThan(200));
      expect(start.left, greaterThan(700)); // at the row's right end
      // Title and Start share a line.
      expect((tester.getCenter(find.text('Flow')).dy - start.center.dy).abs(), lessThan(8));
      // Moods are a wrapped chip row, not a scroller.
      expect(find.byType(ListView), findsNothing);
      expect(find.text('Any mood'), findsOneWidget);
    });

    testWidgets('chips pick a mood and Space starts Flow from the keyboard', (tester) async {
      await size(tester, const Size(1280, 800), desktop: true);
      final calls = <String>[];
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), calls));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();
      expect(calls, ['mood:happy']);
      expect(find.text('Starts with Happy.'), findsOneWidget);
      // The first Tab lands on Start; Space (then Enter) activates it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['mood:happy', 'start', 'start']);
    });

    testWidgets('hovering Start shows its tooltip', (tester) async {
      await size(tester, const Size(1280, 800), desktop: true);
      await tester.pumpWidget(flowApp(const FlowSection(), const FlowState(), []));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Start Flow')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(Tooltip), findsWidgets);
    });
  });
}
