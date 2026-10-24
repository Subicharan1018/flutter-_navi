import 'dart:async';

/// A FIFO mutual-exclusion lock for async work.
///
/// `run` bodies execute strictly one at a time, in call order. Unlike the
/// "await the previous completer, then install mine" pattern, two waiters can
/// never both wake on the same release and run together: each caller chains
/// onto the tail left by the caller before it.
///
/// Not re-entrant — a body must not call `run` on the same lock (it would
/// wait for itself). Keep locked bodies to "read live state, decide, commit";
/// do network I/O outside and validate on commit.
class AsyncLock {
  Future<void> _tail = Future<void>.value();
  int _depth = 0;

  /// True while a body is running or queued.
  bool get isLocked => _depth > 0;

  Future<T> run<T>(Future<T> Function() body) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    _depth++;
    return () async {
      try {
        await previous;
        return await body();
      } finally {
        _depth--;
        released.complete();
      }
    }();
  }

  /// Completes once everything queued before this call has finished.
  Future<void> get idle => _tail;
}
