import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/idle_trim.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trims after the window has been out of sight for the delay', () {
    var trims = 0;
    final t = IdleTrim(after: const Duration(milliseconds: 20), trim: () => trims++);
    t.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(trims, 0);
    return Future<void>.delayed(const Duration(milliseconds: 60)).then((_) {
      expect(trims, 1);
      t.dispose();
    });
  });

  test('coming back before the delay cancels it', () async {
    var trims = 0;
    final t = IdleTrim(after: const Duration(milliseconds: 30), trim: () => trims++);
    t.didChangeAppLifecycleState(AppLifecycleState.hidden);
    t.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(trims, 0);
    t.dispose();
  });

  test('the real trim runs without error on an empty cache', () async {
    final t = IdleTrim(after: Duration.zero);
    t.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    t.dispose();
    expect(PaintingBinding.instance.imageCache.currentSize, 0);
  });
}
