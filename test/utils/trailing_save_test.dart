import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/utils/trailing_save.dart';

void main() {
  test('a burst of resize events saves once, after the burst ends', () {
    fakeAsync((async) {
      var saves = 0;
      final save = TrailingSave(const Duration(milliseconds: 400), () async => saves++);
      for (var i = 0; i < 30; i++) {
        save.schedule();
        async.elapse(const Duration(milliseconds: 16)); // a drag, one event per frame
      }
      expect(saves, 0, reason: 'nothing is written while the window is still being dragged');
      async.elapse(const Duration(milliseconds: 400));
      expect(saves, 1);
    });
  });

  test('flush saves at once and cancels the pending save', () {
    fakeAsync((async) {
      var saves = 0;
      final save = TrailingSave(const Duration(milliseconds: 400), () async => saves++);
      save.schedule();
      save.flush();
      expect(saves, 1, reason: 'closing the window must not wait for the timer');
      async.elapse(const Duration(seconds: 2));
      expect(saves, 1);
    });
  });

  test('flush with nothing pending does nothing', () {
    fakeAsync((async) {
      var saves = 0;
      final save = TrailingSave(const Duration(milliseconds: 400), () async => saves++);
      save.flush();
      expect(saves, 0);
    });
  });

  test('a failing save does not stop later ones', () {
    fakeAsync((async) {
      var calls = 0;
      final save = TrailingSave(const Duration(milliseconds: 100), () async {
        calls++;
        if (calls == 1) throw StateError('disk busy');
      });
      save.schedule();
      async.elapse(const Duration(milliseconds: 150));
      save.schedule();
      async.elapse(const Duration(milliseconds: 150));
      expect(calls, 2);
    });
  });
}
