import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/utils/async_lock.dart';

void main() {
  test('bodies never overlap and run in call order', () async {
    final lock = AsyncLock();
    var inside = 0;
    var maxInside = 0;
    final order = <int>[];
    await Future.wait([
      for (var i = 0; i < 20; i++)
        lock.run(() async {
          inside++;
          maxInside = inside > maxInside ? inside : maxInside;
          await Future<void>.delayed(Duration(milliseconds: (20 - i) % 4));
          order.add(i);
          inside--;
        }),
    ]);
    expect(maxInside, 1);
    expect(order, List.generate(20, (i) => i));
  });

  test('two waiters released by the same holder do not both run', () async {
    // The old "await previous completer, then install mine" pattern let every
    // waiter of one release proceed together. Here the 2nd and 3rd must queue.
    final lock = AsyncLock();
    final gate = Completer<void>();
    final events = <String>[];
    final a = lock.run(() async {
      events.add('a+');
      await gate.future;
      events.add('a-');
    });
    final b = lock.run(() async {
      events.add('b+');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add('b-');
    });
    final c = lock.run(() async => events.add('c'));
    gate.complete();
    await Future.wait([a, b, c]);
    expect(events, ['a+', 'a-', 'b+', 'b-', 'c']);
  });

  test('an error releases the lock and reaches the caller', () async {
    final lock = AsyncLock();
    await expectLater(lock.run<void>(() async => throw StateError('boom')), throwsStateError);
    expect(await lock.run(() async => 42), 42);
    expect(lock.isLocked, isFalse);
  });

  test('idle waits for work queued before it', () async {
    final lock = AsyncLock();
    var done = false;
    unawaited(lock.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      done = true;
    }));
    await lock.idle;
    expect(done, isTrue);
  });
}
