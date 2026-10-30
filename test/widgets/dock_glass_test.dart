import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/dock_glass.dart';
import 'package:navivibe/widgets/ui/large_title_page.dart';

const _dockHeight = 190.0;
const _rows = 40;

Widget _shell({
  MotionLevel motion = MotionLevel.full,
  bool highContrast = false,
  Widget? dockProbe,
}) {
  return ThemeTokens(
    tokens: AppThemeTokens.fallback,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(highContrast: highContrast),
        child: MotionScope.resolve(level: motion, systemReduced: false, child: child!),
      ),
      home: Scaffold(
        body: Stack(
          children: [
            DockInsetScope(
              child: LargeTitlePage(
                title: 'Jam',
                slivers: [
                  SliverList.builder(
                    itemCount: _rows,
                    itemBuilder: (_, i) => SizedBox(key: ValueKey('row$i'), height: 50, child: Text('row $i')),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassDock(
                ground: const Color(0xFF101010),
                // Stand-ins for the Jam pill, mini player and tab bar.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 40),
                    const SizedBox(height: 58),
                    const SizedBox(height: 62),
                    SizedBox(height: _dockHeight - 160 - Space.sm, child: dockProbe),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

int _blurs(WidgetTester tester) => tester
    .widgetList<BackdropFilter>(find.byType(BackdropFilter))
    .where((b) => b.filter == ui.ImageFilter.blur(sigmaX: GlassDock.sigma, sigmaY: GlassDock.sigma, tileMode: TileMode.clamp))
    .length;

void main() {
  setUp(() {
    GlassGovernor.reset();
    DockInset.height.value = 0;
    PlatformUtils.debugTvOverride = null;
  });
  tearDown(() => PlatformUtils.debugTvOverride = null);

  group('padding', () {
    testWidgets('the last row scrolls fully above the dock', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pump();
      await tester.pump();
      expect(DockInset.height.value, closeTo(tester.getSize(find.byType(GlassDock)).height, 0.5));

      await tester.fling(find.byType(Scrollable).first, const Offset(0, -6000), 6000);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(Scrollable).first, const Offset(0, -6000), 6000);
      await tester.pumpAndSettle();

      final last = tester.getRect(find.byKey(const ValueKey('row${_rows - 1}')));
      final dockTop = tester.getTopLeft(find.byType(GlassDock)).dy;
      expect(last.bottom, lessThanOrEqualTo(dockTop + 0.5));
    });

    testWidgets('without a dock a page keeps only the safe-area clearance', (tester) async {
      await tester.pumpWidget(ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: MaterialApp(home: Builder(builder: (c) => Text('${dockClearance(c)}'))),
      ));
      expect(find.text('${Space.lg}'), findsOneWidget);
    });
  });

  group('glass vs solid fallback', () {
    testWidgets('Full motion: exactly one blur layer for the whole dock', (tester) async {
      await tester.pumpWidget(_shell());
      expect(_blurs(tester), 1);
    });

    testWidgets('Reduced motion falls back to the solid band', (tester) async {
      await tester.pumpWidget(_shell(motion: MotionLevel.reduced));
      expect(_blurs(tester), 0);
    });

    testWidgets('high contrast falls back to the solid band', (tester) async {
      await tester.pumpWidget(_shell(highContrast: true));
      expect(_blurs(tester), 0);
    });

    testWidgets('a TV never gets glass', (tester) async {
      PlatformUtils.debugTvOverride = true;
      await tester.pumpWidget(_shell());
      expect(_blurs(tester), 0);
    });

    testWidgets('a device judged too slow drops to solid, live', (tester) async {
      await tester.pumpWidget(_shell());
      expect(_blurs(tester), 1);
      for (var i = 0; i < GlassGovernor.window; i++) {
        GlassGovernor.report(const Duration(milliseconds: 40));
      }
      await tester.pump();
      expect(_blurs(tester), 0);
    });

    testWidgets('capsules know whether they sit on glass', (tester) async {
      late bool on;
      Widget probe() => Builder(builder: (c) {
            on = DockGlass.of(c);
            return const SizedBox();
          });
      await tester.pumpWidget(_shell(dockProbe: probe()));
      expect(on, isTrue);
      await tester.pumpWidget(_shell(motion: MotionLevel.reduced, dockProbe: probe()));
      expect(on, isFalse);
    });
  });

  group('GlassGovernor', () {
    test('fast frames never trip it', () {
      for (var i = 0; i < GlassGovernor.window * 3; i++) {
        GlassGovernor.report(const Duration(milliseconds: 8));
      }
      expect(GlassGovernor.tooSlow.value, isFalse);
    });

    test('a few hitches in a window do not trip it', () {
      for (var i = 0; i < GlassGovernor.window; i++) {
        GlassGovernor.report(Duration(milliseconds: i % 10 == 0 ? 40 : 8));
      }
      expect(GlassGovernor.tooSlow.value, isFalse);
    });

    test('sustained slow frames trip it once, at the end of a window', () {
      for (var i = 0; i < GlassGovernor.window - 1; i++) {
        expect(GlassGovernor.report(const Duration(milliseconds: 30)), isFalse);
      }
      expect(GlassGovernor.report(const Duration(milliseconds: 30)), isTrue);
      expect(GlassGovernor.tooSlow.value, isTrue);
    });
  });

  group('frame time', () {
    Future<double> scrollCost(WidgetTester tester, MotionLevel level) async {
      await tester.pumpWidget(_shell(motion: level));
      await tester.pump();
      final sw = Stopwatch()..start();
      final g = await tester.startGesture(tester.getCenter(find.byType(Scrollable).first));
      for (var i = 0; i < 30; i++) {
        await g.moveBy(const Offset(0, -24));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      sw.stop();
      return sw.elapsedMicroseconds / 30 / 1000;
    }

    testWidgets('scrolling under the glass dock stays inside a frame budget', (tester) async {
      final glass = await scrollCost(tester, MotionLevel.full);
      final solid = await scrollCost(tester, MotionLevel.reduced);
      // Build+layout+paint of the widget tree on the test host (the GPU blur
      // itself only shows up on a device). A generous ceiling catches an
      // accidental per-frame rebuild of the whole dock or page.
      // ignore: avoid_print
      print('dock scroll frame: glass ${glass.toStringAsFixed(2)} ms, solid ${solid.toStringAsFixed(2)} ms');
      expect(glass, lessThan(60));
      expect(glass, lessThan(solid * 3 + 10));
    });
  });
}
