import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/exportify_import/data/exportify_models.dart';
import 'package:navivibe/features/exportify_import/logic/import_finished.dart';
import 'package:navivibe/services/app_notifier.dart';

Map<String, dynamic> _json(int id, {Map<String, dynamic>? finished}) => {
      'id': id,
      'name': 'List $id',
      'plan': {'status': 'idle'},
      'finished': ?finished,
    };

ExportifySummary _imp(int id, {Map<String, dynamic>? finished}) => ExportifySummary.fromJson(_json(id, finished: finished));

void main() {
  test('the finished record is optional on the wire', () {
    expect(_imp(1).finished, isNull);
    expect(_imp(1, finished: {'fetched': 3}).finished, isNull, reason: 'no finished_at: no identity');
    final f = _imp(1, finished: {'fetched': 12, 'failed': 2, 'finished_at': '2026-11-23T10:00:00Z'}).finished!;
    expect((f.fetched, f.failed), (12, 2));
  });

  test('first look on a device remembers old runs without announcing them', () {
    final c = checkFinishedImports([_imp(1, finished: {'fetched': 5, 'finished_at': 'a'})], null);
    expect(c.announce, isFalse);
    expect(c.seen, ['1:a']);
  });

  test('a new finished run is announced once', () {
    final all = [_imp(1, finished: {'fetched': 5, 'failed': 1, 'finished_at': 'b'}), _imp(2)];
    final first = checkFinishedImports(all, ['1:a']);
    expect(first.announce, isTrue);
    expect((first.fetched, first.failed, first.imports), (5, 1, 1));
    final again = checkFinishedImports(all, first.seen);
    expect(again.announce, isFalse);
  });

  test('several runs at once add up into one notification', () {
    final c = checkFinishedImports([
      _imp(1, finished: {'fetched': 5, 'finished_at': 'x'}),
      _imp(2, finished: {'fetched': 7, 'finished_at': 'y'}),
    ], <String>[]);
    expect(c.fetched, 12);
    expect(importFinishedText(c).body, 'Your import finished: 12 songs added.');
  });

  test('text names failures and the empty case', () {
    const c = ImportFinishedCheck(seen: [], fetched: 1, failed: 2, imports: 1);
    expect(importFinishedText(c).body, 'Your import finished: 1 song added. 2 songs couldn’t be fetched.');
    const none = ImportFinishedCheck(seen: [], fetched: 0, failed: 0, imports: 1);
    expect(importFinishedText(none).body, 'Your import finished: No new songs were added.');
  });

  test('nothing is posted while the app is on screen', () async {
    final saved = AppNotifier.inForeground;
    addTearDown(() => AppNotifier.inForeground = saved);
    AppNotifier.inForeground = () => true;
    expect(await AppNotifier.show(NotifyChannel.downloads, title: 't', body: 'b'), isFalse);
  });
}
