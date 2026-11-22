import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/player/offline_notice.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('a blink offline never shows the notice', () {
    final g = OfflineNoticeGate();
    g.update(offline: true, now: at(0));
    expect(g.tick(at(500)), isFalse);
    expect(g.update(offline: false, now: at(900)), isFalse);
    expect(g.tick(at(20000)), isFalse);
  });

  test('shows after the settle time, clears after stable reconnect', () {
    final g = OfflineNoticeGate();
    g.update(offline: true, now: at(0));
    expect(g.tick(at(1600)), isTrue);
    expect(g.update(offline: false, now: at(10000)), isTrue);
    expect(g.tick(at(14000)), isTrue);
    expect(g.tick(at(15100)), isFalse);
  });

  test('flapping within one outage never shows it twice', () {
    final g = OfflineNoticeGate();
    var shows = 0;
    var was = false;
    void feed(bool offline, int ms) {
      final v = g.update(offline: offline, now: at(ms));
      if (v && !was) shows++;
      was = v;
    }
    feed(true, 0);
    feed(true, 2000); // shown
    feed(false, 3000);
    feed(true, 5000); // back down before it cleared
    feed(false, 8000);
    feed(true, 10000);
    expect(shows, 1);
    expect(g.visible, isTrue);
  });

  test('a later separate outage shows it again', () {
    final g = OfflineNoticeGate();
    g.update(offline: true, now: at(0));
    g.tick(at(2000));
    g.update(offline: false, now: at(3000));
    expect(g.tick(at(9000)), isFalse);
    g.update(offline: true, now: at(60000));
    expect(g.tick(at(62000)), isTrue);
  });

  test('nextCheck points at the pending change', () {
    final g = OfflineNoticeGate();
    expect(g.nextCheck, isNull);
    g.update(offline: true, now: at(0));
    expect(g.nextCheck, at(1500));
  });

  group('restore waits for the network only when it must', () {
    test('offline and not on the device waits', () {
      expect(needsNetworkToLoad(offline: true, songId: 'a', hasLocalCopy: (_) => false), isTrue);
    });
    test('offline with a downloaded copy loads now', () {
      expect(needsNetworkToLoad(offline: true, songId: 'a', hasLocalCopy: (_) => true), isFalse);
    });
    test('online always loads now', () {
      expect(needsNetworkToLoad(offline: false, songId: 'a', hasLocalCopy: (_) => false), isFalse);
    });
  });
}
