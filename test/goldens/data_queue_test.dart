/// The admin's Data queue screen: an open batch with its result, coverage and history. Phone (390 wide, tall
/// enough to show the whole page) and Windows 1280×800.
///
///   flutter test test/goldens/data_queue_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/data_queue/data/data_queue_models.dart';
import 'package:navivibe/features/data_queue/logic/data_queue_providers.dart';
import 'package:navivibe/features/data_queue/ui/data_queue_screen.dart';
import 'package:navivibe/utils/platform_utils.dart';

import 'golden_fonts.dart';

// The screen words ages from the real clock ("3 days ago"), so the fixtures are built
// from it too: a fixed date made this golden fail the day after it was recorded.
final _now = DateTime.now();

QueueStatus _status({bool open = true}) => QueueStatus(
      waiting: 412,
      batchSize: 200,
      fullBatchReady: !open,
      next: const NextBatch(size: 200, full: true, withIsrc: 188),
      openBatch: open ? QueueBatch(id: 5, state: 'open', size: 200, createdAt: _now.subtract(const Duration(days: 3))) : null,
      coverage: const QueueCoverage(total: 2487, real: 855, predicted: 400, none: 1232),
      waitingBySource: const {'backfill': 380, 'request': 21, 'youtube': 11},
      oldestWaitingDays: 14,
      matchRate: 0.76,
      links: const {
        'soundiiz': 'https://soundiiz.com/tutorial/import-excel-to-soundiiz',
        'tunemymusic': 'https://www.tunemymusic.com/transfer/file-to-spotify',
      },
    );

final _history = [
  QueueBatch(
    id: 4,
    state: 'closed',
    size: 200,
    createdAt: _now.subtract(const Duration(days: 10)),
    summary: const UploadSummary(batchId: 4, matched: 152, notFound: 48, featuresStored: 152, predicted: 48),
  ),
  QueueBatch(id: 3, state: 'released', size: 200, createdAt: _now.subtract(const Duration(days: 45))),
];

class _Actions extends DataQueueActions {
  @override
  DataQueueActionState build() => const DataQueueActionState(
        result: UploadSummary(batchId: 4, rows: 190, matched: 152, notFound: 48, featuresStored: 152, predicted: 48),
      );
}

Widget _app({bool open = true}) {
  final tokens = AppThemeTokens.fallback;
  final overrides = <Override>[
    dataQueueAdminProvider.overrideWithValue(true),
    dataQueueStatusProvider.overrideWith((ref) async => _status(open: open)),
    dataQueueHistoryProvider.overrideWith((ref) async => _history),
    dataQueueActionsProvider.overrideWith(_Actions.new),
  ];
  return ProviderScope(
    overrides: overrides,
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(tokens),
        home: Scaffold(backgroundColor: tokens.bgBase, body: const DataQueueScreen()),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  void view(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  testWidgets('phone', (tester) async {
    view(tester, const Size(390, 1950), 2);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('data_queue/data_queue_phone.png'));
  });

  testWidgets('phone, a full batch is ready', (tester) async {
    view(tester, const Size(390, 1300), 2);
    await tester.pumpWidget(_app(open: false));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('data_queue/data_queue_ready_phone.png'));
  });

  testWidgets('windows', (tester) async {
    PlatformUtils.debugDesktopOverride = true;
    view(tester, const Size(1280, 1300), 1);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('data_queue/data_queue_windows.png'));
  });
}
