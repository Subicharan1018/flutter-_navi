import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/ai_shuffle/ui/widgets/moment_line.dart';

void main() {
  test('the hour is read as the server wrote it, not shifted to local time', () {
    expect(hourOfTimestamp('2026-11-21T10:30:00+05:30'), 10.5);
    expect(hourOfTimestamp('2026-11-21 23:59:00'), closeTo(23.98, 0.01));
  });

  test('a timestamp without a valid time gives no hour', () {
    expect(hourOfTimestamp(''), isNull);
    expect(hourOfTimestamp('2026-11-21'), isNull);
    expect(hourOfTimestamp('2026-11-21T25:00:00'), isNull);
  });

  test('clock labels use 12-hour time', () {
    expect(clockLabel(0), '12:00 AM');
    expect(clockLabel(12.5), '12:30 PM');
    expect(clockLabel(18.25), '6:15 PM');
  });
}
