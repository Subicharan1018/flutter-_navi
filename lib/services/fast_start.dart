import 'dart:async';

import '../player/audio_quality.dart' show isLosslessSuffix;

/// Rules and state machines behind "Fast start" (pure Dart, no player).
///
/// Fast start plays a small low-bitrate copy of a song for the first moments
/// while the full-quality copy downloads in the background, then swaps to it
/// at the same position. The chosen streaming quality stays the final target.

/// The low rate used for the first seconds. 64 kbps mp3 was clearly audible
/// against a lossless song (dull highs, a "swish"), and listeners noticed the
/// swap to full quality. 192 kbps is close to transparent for most ears and
/// still a fraction of a FLAC (about 1/5), so the first audio arrives sooner
/// and the switch is hard to hear.
const int kFastStartLowKbps = 192;
const String kFastStartLowFormat = 'mp3';

/// How long a skip must rest before the song it landed on is opened. Songs
/// passed over faster than this are never requested.
const Duration kSkipSettle = Duration(milliseconds: 250);

/// The same wait when the song the skip landed on is already a file on this
/// device (downloaded, or preloaded into the play cache): opening it costs no
/// request, so a quick skip past it wastes nothing and the wait can be short.
const Duration kSkipSettleReady = Duration(milliseconds: 80);

/// Songs shorter than this are not worth two requests.
const int kFastStartMinDurationSec = 45;

/// Audio the player wants buffered before it starts (matches the Android
/// load control's `bufferForPlayback`).
const double kFastStartFirstAudioSec = 1.5;

/// The server spawns a transcoder for the low copy; that start-up is not free,
/// so the low copy must save more than this to be worth it.
const double kFastStartMinSavingSec = 0.4;

/// Used until a download has been timed on this connection (a home-server
/// uplink, not a LAN, so the first song of a session still fast-starts).
const int kFastStartAssumedBytesPerSec = 256 * 1024;

/// Fast Start is used only if the full copy can be expected on disk within
/// this long (or 25% of the song, if shorter).
const double kFastStartMaxCatchUpSec = 30;

/// Nothing the swap could still help with is left in the last few seconds.
const int kFastStartMinRemainingMs = 4000;

class FastStartInput {
  const FastStartInput({
    required this.enabled,
    required this.durationSec,
    required this.suffix,
    required this.songKbps,
    this.targetKbps = 0,
    this.alreadyOnDevice = false,
    this.alreadyBuffered = false,
    this.bytesPerSec,
  });

  final bool enabled;
  final int durationSec;
  final String suffix;

  /// The file's own bitrate in kbps (0 = unknown).
  final int songKbps;

  /// The listener's streaming ceiling in kbps (0 = original).
  final int targetKbps;

  /// Downloaded, device-library or finished play-cache copy.
  final bool alreadyOnDevice;

  /// Preloaded: the player or the cache already holds the first part.
  final bool alreadyBuffered;

  /// Measured download speed, or null before any measurement.
  final int? bytesPerSec;
}

class FastStartDecision {
  const FastStartDecision(this.use, this.reason);
  final bool use;
  final String reason;
  @override
  String toString() => 'FastStartDecision(${use ? 'use' : 'skip'}: $reason)';
}

class FastStartPolicy {
  const FastStartPolicy._();

  /// Kbps the song streams at today (what "full" means for this song).
  static int fullKbps(FastStartInput i) {
    final lossless = isLosslessSuffix(i.suffix.toLowerCase());
    if (i.targetKbps > 0) {
      return (!lossless && i.songKbps > 0 && i.songKbps < i.targetKbps) ? i.songKbps : i.targetKbps;
    }
    if (i.songKbps > 0) return i.songKbps;
    return lossless ? 900 : 256;
  }

  static FastStartDecision decide(FastStartInput i) {
    if (!i.enabled) return const FastStartDecision(false, 'setting off');
    if (i.alreadyOnDevice) return const FastStartDecision(false, 'on device');
    if (i.alreadyBuffered) return const FastStartDecision(false, 'preloaded');
    if (i.durationSec > 0 && i.durationSec < kFastStartMinDurationSec) {
      return const FastStartDecision(false, 'short song');
    }
    final lossless = isLosslessSuffix(i.suffix.toLowerCase());
    if (!lossless && i.songKbps > 0 && i.songKbps <= kFastStartLowKbps) {
      return const FastStartDecision(false, 'already low bitrate');
    }
    if (i.targetKbps > 0 && i.targetKbps <= kFastStartLowKbps) {
      return const FastStartDecision(false, 'chosen quality at or below low');
    }
    final full = fullKbps(i);
    final speed = (i.bytesPerSec ?? kFastStartAssumedBytesPerSec).clamp(1, 1 << 40);
    // Time to fetch the first audio, full copy minus low copy.
    final saving = kFastStartFirstAudioSec * (full - kFastStartLowKbps) * 125 / speed;
    if (saving < kFastStartMinSavingSec) {
      return FastStartDecision(false, 'fast link (saves ${saving.toStringAsFixed(2)}s)');
    }
    // The swap only happens once the whole full copy is on disk. A song whose
    // full copy would take longer than this to arrive would play at the low
    // rate for good (a 24-bit FLAC over a home uplink takes minutes).
    if (i.durationSec > 0) {
      final catchUpSec = full * 125 * i.durationSec / speed;
      final limit = [kFastStartMaxCatchUpSec, i.durationSec * 0.25].reduce((a, b) => a < b ? a : b);
      if (catchUpSec > limit) {
        return FastStartDecision(
          false,
          'full copy would not catch up (${catchUpSec.toStringAsFixed(0)}s > ${limit.toStringAsFixed(0)}s)',
        );
      }
    }
    return FastStartDecision(true, 'saves ~${saving.toStringAsFixed(2)}s');
  }

  /// Swap to the full copy only when it is fully on disk, the same song is
  /// still current, and enough of the song is left to matter.
  static bool shouldSwap({
    required bool fullReady,
    required bool sameSong,
    required bool skipPending,
    required int positionMs,
    required int durationMs,
  }) {
    if (!fullReady || !sameSong || skipPending) return false;
    if (durationMs <= 0) return true;
    return durationMs - positionMs > kFastStartMinRemainingMs;
  }
}

/// Smoothed download speed from timed transfers.
class ThroughputTracker {
  ThroughputTracker({this.alpha = 0.4});
  static final ThroughputTracker instance = ThroughputTracker();

  final double alpha;
  double? _bps;
  int? get bytesPerSec => _bps?.round();

  /// Ignores transfers too small or too quick to say anything.
  void add(int bytes, Duration elapsed) {
    if (bytes < 64 * 1024 || elapsed.inMilliseconds < 150) return;
    final sample = bytes / (elapsed.inMilliseconds / 1000);
    final prev = _bps;
    _bps = prev == null ? sample : prev + alpha * (sample - prev);
  }

  void reset() => _bps = null;
}

/// Debounces skips. Each [request] restarts the timer; only the index the
/// listener rests on is [load]ed, and any load already running becomes stale.
///
/// [load] gets an `isStale` probe it must check after each await so a
/// superseded load never touches the player after a newer one began.
class SkipCoordinator {
  SkipCoordinator({
    required this.load,
    this.settle = kSkipSettle,
    this.settleFor,
    this.onError,
  });

  final Future<void> Function(int index, bool Function() isStale) load;
  final Duration settle;

  /// A shorter wait for an index that costs nothing to open (see
  /// [kSkipSettleReady]); null or a longer answer falls back to [settle].
  final Duration Function(int index)? settleFor;
  final void Function(Object error, StackTrace stack)? onError;

  Timer? _timer;
  int? _pending;
  int _generation = 0;
  int _running = 0;

  /// The index the listener has skipped to but nothing was loaded for yet.
  int? get pendingIndex => _pending;
  bool get hasPending => _pending != null;
  bool get isLoading => _running > 0;
  bool get isBusy => hasPending || isLoading;

  /// Rests on [index] for [settle], then loads it. A zero [settle] loads at once.
  void request(int index) {
    _generation++;
    _pending = index;
    _timer?.cancel();
    final custom = settleFor?.call(index);
    final wait = custom != null && custom < settle ? custom : settle;
    if (wait == Duration.zero) {
      _fire();
    } else {
      _timer = Timer(wait, _fire);
    }
  }

  /// An explicit choice (tapping a queue row): no waiting.
  Future<void> loadNow(int index) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    final gen = ++_generation;
    return _run(index, gen, rethrowErrors: true);
  }

  /// Drops a pending skip and makes a running load stale.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _generation++;
  }

  void dispose() => cancel();

  void _fire() {
    _timer = null;
    final index = _pending;
    if (index == null) return;
    _pending = null;
    unawaited(_run(index, _generation));
  }

  Future<void> _run(int index, int gen, {bool rethrowErrors = false}) async {
    _running++;
    try {
      await load(index, () => gen != _generation);
    } catch (e, st) {
      onError?.call(e, st);
      if (rethrowErrors) rethrow;
    } finally {
      _running--;
    }
  }
}

/// Stopwatch from "the listener asked for a song" to its first sound.
class FirstAudioProbe {
  final Stopwatch _watch = Stopwatch();
  String? _label;

  bool get running => _watch.isRunning;

  void begin(String label) {
    _label = label;
    _marks.clear();
    _watch
      ..reset()
      ..start();
  }

  final List<String> _marks = [];

  /// Notes a step on the way ("settled", "seek done"); shown with the result.
  void mark(String step) {
    if (_watch.isRunning) _marks.add('$step ${_watch.elapsedMilliseconds}');
  }

  /// Returns "label: N ms (steps)" once, then null until the next [begin].
  String? firstAudio() {
    if (!_watch.isRunning) return null;
    _watch.stop();
    final steps = _marks.isEmpty ? '' : ' [${_marks.join(', ')}]';
    return '$_label: ${_watch.elapsedMilliseconds} ms$steps';
  }
}

/// Preloading the next songs at full quality starts once the current one is
/// past 25% or 20 s, whichever is later: skipped-early songs cost nothing.
bool nextPreloadDue({required int positionMs, required int durationMs}) {
  final threshold = durationMs <= 0
      ? 20000
      : (durationMs * 0.25 > 20000 ? (durationMs * 0.25).round() : 20000);
  return positionMs >= threshold;
}

