/// `items.map(fn)`, awaited, with at most [limit] calls in flight at once, in
/// order. A queue of 200 songs looked up with `Future.wait(items.map(...))` is
/// 200 simultaneous requests: slow, heavy on a phone's data, and it starves
/// everything else on the connection.
Future<List<R>> mapBounded<T, R>(List<T> items, int limit, Future<R> Function(T item) fn) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  }

  final workers = limit < 1 ? 1 : (limit > items.length ? items.length : limit);
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  return [for (final r in results) r as R];
}
