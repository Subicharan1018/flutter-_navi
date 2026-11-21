/// What a device loads first when playback is handed to it: the playing song
/// and the next few ([first]), so it can say "ready" inside the server's few
/// seconds; the other upcoming songs ([rest]) are added once playback has moved.
/// Songs before the playing one are history and are not carried over.
({List<String> first, List<String> rest}) handoverWindow({
  required List<String> queue,
  required String? trackId,
  required int queueIndex,
  int window = 10,
}) {
  if (queue.isEmpty) {
    return (first: [?trackId], rest: const []);
  }
  var from = trackId == null ? -1 : queue.indexOf(trackId);
  if (from < 0) from = queueIndex.clamp(0, queue.length - 1);
  final upcoming = queue.sublist(from);
  final n = window < 1 ? 1 : window;
  return (first: upcoming.take(n).toList(), rest: upcoming.skip(n).toList());
}
