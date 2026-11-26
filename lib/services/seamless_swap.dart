import 'dart:async';

/// The low-rate -> full-quality swap of Fast Start, done as an overlap so the
/// listener never hears silence (pure Dart; the player is behind [SwapVoice]).
///
/// How: a second, short-lived player opens the finished full copy on disk and
/// starts silently a little ahead of the main player, aligned to its position.
/// The two are cross-faded (the same song, so a straight linear fade keeps the
/// loudness level). While the helper alone is audible, the main player reloads
/// the full copy silently, is aligned to the helper, and the fade runs back.
/// Nothing is ever muted, so there is no gap, click or jump in position.

/// How far ahead of the other voice a voice starts, to cover the time its
/// first sound takes to reach the speaker after a seek.
const Duration kSwapLead = Duration(milliseconds: 120);

/// Length of each cross-fade, and the number of volume steps in it.
const Duration kSwapFade = Duration(milliseconds: 240);
const int kSwapFadeSteps = 8;

/// Two voices closer than this in song position are one voice to the ear.
const Duration kSwapAlignTolerance = Duration(milliseconds: 35);

/// Alignment attempts before the swap goes ahead with the best it has.
const int kSwapAlignTries = 3;

/// Position error beyond which the swap is abandoned rather than audibly off.
const Duration kSwapGiveUpDrift = Duration(milliseconds: 250);

/// Linear gains for a cross-fade: [out] falls 1 -> 0 and [inn] rises 0 -> 1.
/// Same material from two encodes is correlated, so the gains sum to 1 and
/// the level stays flat (an equal-power curve would bump by 3 dB mid-fade).
List<({double out, double inn})> crossfadeGains({int steps = kSwapFadeSteps}) => [
  for (var i = 1; i <= steps; i++) (out: 1 - i / steps, inn: i / steps),
];

/// One of the two players taking part in the swap.
abstract class SwapVoice {
  Duration get position;
  Future<void> setVolume(double v);
  Future<void> seek(Duration to);
}

enum SwapOutcome { done, aborted }

class SwapStats {
  SwapStats({
    this.alignDriftMs = const [],
    this.reloadMs = 0,
    this.outcome = SwapOutcome.done,
  });

  /// Position error (ms) the aligner measured before each correction.
  final List<int> alignDriftMs;
  final int reloadMs;
  final SwapOutcome outcome;

  @override
  String toString() => 'SwapStats($outcome, drift=$alignDriftMs, reload=${reloadMs}ms)';
}

class SeamlessSwap {
  SeamlessSwap({
    required this.main,
    required this.helper,
    required this.baseVolume,
    required this.openHelper,
    required this.reloadMain,
    required this.closeHelper,
    required this.isAborted,
    this.wait = _defaultWait,
    this.lead = kSwapLead,
    this.fade = kSwapFade,
    this.onStep,
  });

  /// Called at each stage ("helper aligned", "fade out done", ...), for logs.
  final void Function(String step)? onStep;

  final SwapVoice main;
  final SwapVoice helper;

  /// The volume both voices are at when fully "up" (ReplayGain and fades applied).
  final double Function() baseVolume;

  /// Loads the full copy in the helper and has it playing silently at [at].
  final Future<void> Function(Duration at) openHelper;

  /// Reloads the main player with the full copy at [at], silent and playing.
  final Future<void> Function(Duration at) reloadMain;
  final Future<void> Function() closeHelper;
  final bool Function() isAborted;
  final Future<void> Function(Duration) wait;
  final Duration lead;
  final Duration fade;

  static Future<void> _defaultWait(Duration d) => Future<void>.delayed(d);

  Future<SwapStats> run() async {
    final drifts = <int>[];
    var reloadMs = 0;
    var helperOpen = false;
    try {
      await openHelper(main.position + lead);
      helperOpen = true;
      await helper.setVolume(0);
      if (isAborted()) return await _abort(drifts, reloadMs);
      if (!await _align(follow: helper, leader: main, drifts: drifts)) return await _abort(drifts, reloadMs);
      if (isAborted()) return await _abort(drifts, reloadMs);

      onStep?.call('helper aligned');
      await _fade(from: main, to: helper);
      onStep?.call('helper carries');
      if (isAborted()) return await _abort(drifts, reloadMs);

      final watch = Stopwatch()..start();
      await main.setVolume(0);
      await reloadMain(helper.position);
      await main.setVolume(0); // a reload may reset it
      reloadMs = watch.elapsedMilliseconds;
      if (isAborted()) return await _abort(drifts, reloadMs);
      if (!await _align(follow: main, leader: helper, drifts: drifts)) return await _abort(drifts, reloadMs);
      if (isAborted()) return await _abort(drifts, reloadMs);

      onStep?.call('main aligned');
      await _fade(from: helper, to: main);
      onStep?.call('main carries');
      return SwapStats(alignDriftMs: drifts, reloadMs: reloadMs);
    } catch (_) {
      await _restoreMain();
      rethrow;
    } finally {
      if (helperOpen) await closeHelper();
    }
  }

  /// Puts [follow] where [leader] will be a [lead] from now. Returns false
  /// when it cannot get close enough.
  Future<bool> _align({
    required SwapVoice follow,
    required SwapVoice leader,
    required List<int> drifts,
  }) async {
    // How far ahead to aim: [lead] to begin with, then corrected by the error
    // seen, which learns what a seek really costs on this device.
    var aim = lead;
    for (var i = 0; i < kSwapAlignTries; i++) {
      // Wait for the follower to actually be running before measuring.
      await wait(const Duration(milliseconds: 40));
      final drift = follow.position - leader.position;
      drifts.add(drift.inMilliseconds);
      if (drift.abs() <= kSwapAlignTolerance) return true;
      if (isAborted()) return false;
      aim -= drift;
      await follow.seek(leader.position + aim);
    }
    final last = (follow.position - leader.position).abs();
    drifts.add((follow.position - leader.position).inMilliseconds);
    return last <= kSwapGiveUpDrift;
  }

  Future<void> _fade({required SwapVoice from, required SwapVoice to}) async {
    final gains = crossfadeGains();
    final step = fade ~/ gains.length;
    final base = baseVolume();
    for (final g in gains) {
      await Future.wait([from.setVolume(base * g.out), to.setVolume(base * g.inn)]);
      await wait(step);
    }
  }

  Future<SwapStats> _abort(List<int> drifts, int reloadMs) async {
    await _restoreMain();
    return SwapStats(alignDriftMs: drifts, reloadMs: reloadMs, outcome: SwapOutcome.aborted);
  }

  Future<void> _restoreMain() async {
    try {
      await main.setVolume(baseVolume());
    } catch (_) {}
  }
}

/// Measures the audible interruption of a timeline of (time, total output
/// gain) samples: the longest stretch where the sum of the voices' volumes
/// sits below [floor] of the normal level. A clean swap reads 0 ms.
class InterruptionMeter {
  InterruptionMeter({this.floor = 0.9});
  final double floor;
  final List<({int ms, double level})> _samples = [];

  void add(int ms, double level) => _samples.add((ms: ms, level: level));

  int get maxGapMs {
    var worst = 0;
    int? since;
    for (final s in _samples) {
      if (s.level < floor) {
        since ??= s.ms;
        worst = worst < s.ms - since ? s.ms - since : worst;
      } else {
        since = null;
      }
    }
    return worst;
  }
}
