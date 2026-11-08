import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/widgets/fetch_results_table.dart';
import 'package:navivibe/utils/platform_utils.dart';

const _owned = FetchCandidate(id: 1, title: 'Owned One', artist: 'A', album: 'X', score: 1, kind: FetchKind.original, inLibrary: true, aiChecked: true);
const _new = FetchCandidate(id: 2, title: 'New Song', artist: 'B', album: 'Y', score: 1, kind: FetchKind.original, inLibrary: false, aiChecked: true);
const _artist = FetchCandidate(id: 3, title: 'Some Artist', artist: '', album: '', score: 1, kind: FetchKind.original, inLibrary: false, aiChecked: true, type: FetchSearchType.artist);

Future<void> _pump(WidgetTester tester, {required List<FetchCandidate> items, Set<int>? picked, required List<String> log}) async {
  PlatformUtils.debugDesktopOverride = true;
  addTearDown(() => PlatformUtils.debugDesktopOverride = null);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [fetchJobsProvider.overrideWith(FetchJobsController.new)],
    child: MaterialApp(
      theme: AppTheme.build(AppThemeTokens.fallback),
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: FetchResultsTable(
            candidates: items,
            picked: picked,
            onPrimary: (c) => log.add('primary ${c.id}'),
            onPlayOwned: (c) => log.add('play ${c.id}'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('rows are 48 px with a square 36 px cover', (tester) async {
    await _pump(tester, items: const [_owned, _new], log: []);
    for (final id in [1, 2]) {
      expect(tester.getSize(find.byKey(ValueKey('fetch-row-$id'))).height, FetchResultsTable.rowHeight);
    }
    expect(FetchResultsTable.rowHeight, 48);
    expect(FetchResultsTable.art, 36);
  });

  testWidgets('a click plays an owned song and downloads a new one', (tester) async {
    final log = <String>[];
    await _pump(tester, items: const [_owned, _new], log: log);
    await tester.tap(find.text('Owned One'));
    await tester.tap(find.text('New Song'));
    expect(log, ['play 1', 'primary 2']);
  });

  testWidgets('Enter on the focused row does what a click does', (tester) async {
    final log = <String>[];
    await _pump(tester, items: const [_new], log: log);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(log, ['primary 2']);
  });

  testWidgets('right-click opens a menu with the same action and Copy Title', (tester) async {
    final log = <String>[];
    await _pump(tester, items: const [_new], log: log);
    final g = await tester.startGesture(tester.getCenter(find.text('New Song')), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Copy Title'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(log, ['primary 2']);
  });

  testWidgets('an artist row says it opens their songs', (tester) async {
    final log = <String>[];
    await _pump(tester, items: const [_artist], log: log);
    await tester.tap(find.text('Some Artist'));
    expect(log, ['primary 3']);
  });

  testWidgets('hovering a row tints it', (tester) async {
    await _pump(tester, items: const [_new], log: []);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('New Song')));
    await tester.pump();
    final tinted = find.descendant(of: find.byKey(const ValueKey('fetch-row-2')), matching: find.byType(DecoratedBox)).evaluate().where((e) {
      final d = (e.widget as DecoratedBox).decoration;
      return d is BoxDecoration && d.color != null;
    });
    expect(tinted, isNotEmpty);
  });
}
