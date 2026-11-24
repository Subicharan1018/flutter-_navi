import 'dart:async';

import 'android_integration.dart';
import 'pill_prefs.dart';

/// Text of the ongoing "downloading" notification.
({String title, String text}) downloadProgressText({required int done, required int total}) {
  final shown = done >= total ? total : done + 1; // the one in flight
  return (
    title: total <= 1 ? 'Downloading a song' : 'Downloading songs',
    text: total <= 1 ? 'Saving for offline listening' : '$shown of $total',
  );
}

/// Keeps the app's process alive while downloads run in the background.
///
/// On Android that is a foreground service ([AndroidIntegration.startDownloadService])
/// with a progress notification; on other platforms nothing is needed, so the
/// default hooks do nothing there. The service exists only while there is work:
/// [update] with `total == 0` (or [stop]) ends it.
class DownloadKeepAlive {
  DownloadKeepAlive({
    Future<bool> Function(String title, String text, int done, int total)? start,
    Future<void> Function()? stop,
    this.minGap = const Duration(seconds: 1),
    DateTime Function()? now,
  })  : _start = start ??
            ((title, text, done, total) =>
                AndroidIntegration.startDownloadService(title: title, text: text, done: done, total: total, live: Pill.downloads.on)),
        _stop = stop ?? AndroidIntegration.stopDownloadService,
        _now = now ?? DateTime.now;

  final Future<bool> Function(String title, String text, int done, int total) _start;
  final Future<void> Function() _stop;
  final DateTime Function() _now;

  /// Android limits how often a notification may change; progress is shown at
  /// most this often (the first and last updates always go through).
  final Duration minGap;

  bool _running = false;
  DateTime? _lastAt;
  int _lastDone = -1;
  int _lastTotal = -1;

  bool get running => _running;

  /// [done] of [total] jobs have finished. `total == 0` means no work left.
  void update({required int done, required int total}) {
    if (total <= 0) {
      stop();
      return;
    }
    final changed = done != _lastDone || total != _lastTotal;
    final now = _now();
    final last = _lastAt;
    if (_running && (!changed || (last != null && now.difference(last) < minGap && done < total))) return;
    _lastAt = now;
    _lastDone = done;
    _lastTotal = total;
    final t = downloadProgressText(done: done, total: total);
    // Optimistic: a refusal below flips it back so the next update retries.
    _running = true;
    unawaited(_start(t.title, t.text, done, total).then((ok) {
      if (!ok) _running = false;
    }, onError: (_) => _running = false));
  }

  void stop() {
    if (!_running && _lastTotal < 0) return;
    _running = false;
    _lastAt = null;
    _lastDone = -1;
    _lastTotal = -1;
    unawaited(_stop());
  }
}
