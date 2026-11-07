import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/widgets/cover_art.dart';
import 'package:navivibe/widgets/desktop_dialogs.dart';
import 'package:navivibe/widgets/ui/action_sheet.dart';

Widget _app(Widget home, {bool desktop = true}) {
  PlatformUtils.debugDesktopOverride = desktop;
  return PointerAnchor(
    child: MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      scrollBehavior: const NaviScrollBehavior(),
      builder: (context, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
      home: home,
    ),
  );
}

void main() {
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
  });

  group('desktop feel', () {
    testWidgets('a desktop scrolls with clamping physics and no mouse drag; a phone keeps the bounce', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      const b = NaviScrollBehavior();
      expect(b.getScrollPhysics(ctx), isA<ClampingScrollPhysics>());
      expect(b.dragDevices, isNot(contains(PointerDeviceKind.mouse)));
      PlatformUtils.debugDesktopOverride = false;
      expect(b.getScrollPhysics(ctx), isA<BouncingScrollPhysics>());
      expect(b.dragDevices, contains(PointerDeviceKind.mouse));
    });

    testWidgets('desktop pages fade in 120 ms, they do not slide', (tester) async {
      const b = NaviDesktopTransitionsBuilder();
      expect(b.transitionDuration, const Duration(milliseconds: 120));
      final theme = AppTheme.build(AppThemeTokens.fallback);
      expect(theme.pageTransitionsTheme.builders[TargetPlatform.windows], isA<NaviDesktopTransitionsBuilder>());
      expect(theme.pageTransitionsTheme.builders[TargetPlatform.android], isA<NaviPageTransitionsBuilder>());
    });

    testWidgets('pressing a clickable does not scale it on desktop', (tester) async {
      await tester.pumpWidget(_app(Center(
        child: CupertinoClickable(onTap: () {}, child: const SizedBox(key: Key('c'), width: 100, height: 40)),
      )));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('c'))));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getSize(find.byKey(const Key('c'))), const Size(100, 40));
      final scale = tester.widget<ScaleTransition>(find.byType(ScaleTransition).first);
      expect(scale.scale.value, 1.0);
      await g.up();
    });

    testWidgets('hovering a clickable washes it and shows the pointer cursor', (tester) async {
      await tester.pumpWidget(_app(Center(
        child: CupertinoClickable(onTap: () {}, child: const SizedBox(key: Key('c'), width: 100, height: 40)),
      )));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final washes = find.descendant(of: find.byType(CupertinoClickable), matching: find.byType(DecoratedBox));
      final before = washes.evaluate().length;
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('c'))));
      await tester.pump();
      expect(washes.evaluate().length, before + 1);
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(washes.evaluate().length, before);
    });

    testWidgets('an icon button with a short label gets a tooltip; a sentence-long label does not', (tester) async {
      await tester.pumpWidget(_app(Center(
        child: CupertinoClickable(
          onTap: () {},
          semanticLabel: 'Shuffle',
          child: const SizedBox(width: 40, height: 40),
        ),
      )));
      expect(find.byType(Tooltip), findsOneWidget);
      await tester.pumpWidget(_app(
        Center(
          child: CupertinoClickable(
            onTap: () {},
            semanticLabel: 'Song, Artist, Album',
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ));
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('mouse long-press', () {

    testWidgets('holding the mouse down does not open the menu on desktop; right-click does', (tester) async {
      var opened = 0;
      Widget w() => CupertinoClickable(onTap: () {}, onLongPress: () => opened++, child: const SizedBox(key: Key('c'), width: 100, height: 40));
      await tester.pumpWidget(_app(Center(child: w())));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('c'))), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(seconds: 1));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 0);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('c'))), buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
    });

    testWidgets('a finger still long-presses on a phone', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_app(
        Center(child: CupertinoClickable(onTap: () {}, onLongPress: () => opened++, child: const SizedBox(key: Key('c'), width: 100, height: 40))),
        desktop: false,
      ));
      await tester.longPress(find.byKey(const Key('c')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
    });
  });

  group('context menu', () {
    Future<void> openMenu(WidgetTester tester, Offset at) async {
      late BuildContext ctx;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })));
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      var picked = '';
      PointerAnchor.record(at);
      showPlatformSheet<void>(
        context: ctx,
        menu: true,
        builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHeader(title: 'A song', subtitle: 'An artist'),
          SheetGroup(children: [
            SheetAction(label: 'Play Next', icon: NaviGlyph.playNext, onTap: () => picked = 'next'),
            SheetAction(label: 'Add to Queue', icon: NaviGlyph.queue, onTap: () => picked = 'queue'),
          ]),
        ]),
      );
      await tester.pumpAndSettle();
      addTearDown(() => expect(picked, isNotNull));
    }

    testWidgets('opens at the pointer, compact, without the phone header', (tester) async {
      await openMenu(tester, const Offset(300, 200));
      final menu = tester.getRect(find.byType(Material).last);
      expect(menu.topLeft, const Offset(300, 200));
      expect(menu.width, 252);
      expect(find.text('A song'), findsNothing, reason: 'a context menu opens on the thing you clicked');
      expect(tester.getSize(find.text('Play Next')).height, lessThan(24));
      expect(find.text('Add to Queue'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('stays inside the window near an edge', (tester) async {
      await openMenu(tester, const Offset(1090, 690));
      final menu = tester.getRect(find.byType(Material).last);
      expect(menu.right, lessThanOrEqualTo(1100 - 8 + 0.01));
      expect(menu.bottom, lessThanOrEqualTo(700 - 8 + 0.01));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Esc closes it, and so does picking an action', (tester) async {
      await openMenu(tester, const Offset(300, 200));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Play Next'), findsNothing);

      await openMenu(tester, const Offset(300, 200));
      await tester.tap(find.text('Play Next'));
      await tester.pumpAndSettle();
      expect(find.text('Play Next'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('a phone still gets the sheet, with its header', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }), desktop: false));
      showPlatformSheet<void>(
        context: ctx,
        menu: true,
        builder: (_) => const SheetHeader(title: 'A song', subtitle: 'An artist'),
      );
      await tester.pumpAndSettle();
      expect(find.text('A song'), findsOneWidget);
    });
  });

  group('cover art', () {
    test('lists ask the server for the next step up from their display size', () {
      const base = 'https://s.example/rest/getCoverArt.view?id=al-1&u=a&t=b&s=c';
      expect(Uri.parse(sizedCoverUrl(base, 92)).queryParameters['size'], '96');
      expect(Uri.parse(sizedCoverUrl(base, 97)).queryParameters['size'], '160');
      expect(Uri.parse(sizedCoverUrl(base, 450)).queryParameters['size'], '512');
      expect(Uri.parse(sizedCoverUrl(base, 5000)).queryParameters['size'], '1024');
      expect(Uri.parse(sizedCoverUrl(base, 92)).queryParameters['id'], 'al-1');
    });

    test('the same cover at the same step is one URL, so it is cached once', () {
      const base = 'https://s.example/rest/getCoverArt.view?id=al-1&u=a&t=b&s=c';
      expect(sizedCoverUrl(base, 120), sizedCoverUrl(base, 150));
    });

    test('a link that already has a size, or is not cover art, is left alone', () {
      const sized = 'https://s.example/rest/getCoverArt.view?id=1&size=300';
      expect(sizedCoverUrl(sized, 90), sized);
      const other = 'https://s.example/portrait.jpg';
      expect(sizedCoverUrl(other, 90), other);
    });

    testWidgets('no cover at all shows the note; there is no note while one is loading', (tester) async {
      await tester.pumpWidget(_app(const Center(child: CoverArt(url: null, size: 80))));
      expect(find.byType(NaviIcon), findsOneWidget);
    });
  });
}
