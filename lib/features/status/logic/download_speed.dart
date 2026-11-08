/// Rolling bytes-per-second over the last few seconds of downloaded data.
/// Fed by `OfflineService` as bytes arrive; read by the status screen. A
/// download that has stopped reads as 0 once its last bytes age out.
class DownloadSpeedMeter {
  DownloadSpeedMeter._();
  static final DownloadSpeedMeter instance = DownloadSpeedMeter._();
  DownloadSpeedMeter.forTesting();

  static const Duration window = Duration(seconds: 5);

  final List<(DateTime, int)> _chunks = [];
  int _lastReceived = 0;

  /// A new download starts counting from zero received bytes.
  void startFile() => _lastReceived = 0;

  /// Cumulative [received] bytes of the current file, as Dio reports them.
  void record(int received, {DateTime? now}) {
    final delta = received - _lastReceived;
    _lastReceived = received;
    if (delta <= 0) return;
    final t = now ?? DateTime.now();
    _chunks.add((t, delta));
    _trim(t);
  }

  void _trim(DateTime now) {
    final cutoff = now.subtract(window);
    _chunks.removeWhere((c) => c.$1.isBefore(cutoff));
  }

  /// Bytes per second over the window; 0 when nothing arrived recently.
  double bytesPerSecond({DateTime? now}) {
    final t = now ?? DateTime.now();
    _trim(t);
    if (_chunks.isEmpty) return 0;
    final total = _chunks.fold<int>(0, (a, c) => a + c.$2);
    final span = t.difference(_chunks.first.$1).inMilliseconds;
    return total / (span < 1000 ? 1.0 : span / 1000);
  }
}
