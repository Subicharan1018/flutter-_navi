

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/utils/bounded_map.dart';

void main() {
  test('never runs more than the limit at once, and keeps the order', () async {
    var running = 0, peak = 0;
    final out = await mapBounded<int, int>(List.generate(40, (i) => i), 6, (i) async {
      running++;
      peak = peak < running ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      running--;
      return i * 2;
    });
    expect(peak, lessThanOrEqualTo(6));
    expect(peak, greaterThan(1), reason: 'it still runs in parallel');
    expect(out, [for (var i = 0; i < 40; i++) i * 2]);
  });

  test('an empty list answers at once', () async {
    expect(await mapBounded<int, int>(const [], 4, (i) async => i), isEmpty);
  });

  test('one failure does not lose the others when the callback catches it', () async {
    final out = await mapBounded<int, int?>([1, 2, 3], 2, (i) async => i == 2 ? null : i);
    expect(out, [1, null, 3]);
  });
}
