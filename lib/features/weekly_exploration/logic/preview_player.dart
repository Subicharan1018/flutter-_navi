import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../providers/player_provider.dart';
import '../data/weekly_models.dart';
import 'weekly_providers.dart';

/// The thing that makes sound for a 30 s preview. Its own player: the listener's queue is never touched.
abstract class PreviewEngine {
  /// Position in the clip, about four times a second while it plays.
  Stream<Duration> get position;

  /// Fires once when the clip reaches its end.
  Stream<void> get completed;

  /// Loads [url] and starts it. Throws when it cannot.
  Future<void> play(String url);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioPreviewEngine implements PreviewEngine {
  AudioPlayer? _p;

  AudioPlayer get _player => _p ??= AudioPlayer();

  @override
  Stream<Duration> get position => _player.createPositionStream(minPeriod: const Duration(milliseconds: 200));

  @override
  Stream<void> get completed => _player.processingStateStream.where((s) => s == ProcessingState.completed);

  @override
  Future<void> play(String url) async {
    await _player.setUrl(url);
    unawaited(_player.play());
  }

  @override
  Future<void> stop() async => _p?.stop();

  @override
  Future<void> dispose() async {
    await _p?.dispose();
    _p = null;
  }
}

final previewEngineProvider = Provider<PreviewEngine>((ref) {
  final e = JustAudioPreviewEngine();
  ref.onDispose(e.dispose);
  return e;
});

/// Stops whatever the listener has playing, so the clip is not heard on top of it. Overridden in tests.
final previewPauseMainProvider = Provider<Future<void> Function()>((ref) => () async {
      try {
        await ref.read(playerProvider.notifier).pause();
      } catch (_) {}
    });

enum PreviewStatus { idle, loading, playing }

@immutable
class PreviewState {
  /// The pick being heard, if any.
  final int? pickId;
  final PreviewStatus status;

  /// "Play all previews": at the end of a clip the next undecided pick starts.
  final bool all;

  /// Set when a clip could not start (the message to show), then cleared by the next tap.
  final String? error;

  const PreviewState({this.pickId, this.status = PreviewStatus.idle, this.all = false, this.error});

  bool playing(int id) => pickId == id && status != PreviewStatus.idle;
}

/// How far into the clip, 0 to 1. Its own provider so only the ring around the playing cover rebuilds.
class PreviewProgress extends Notifier<double> {
  @override
  double build() => 0;
  void set(double v) => state = v;
}

final previewProgressProvider = NotifierProvider<PreviewProgress, double>(PreviewProgress.new);

/// The seconds a preview runs (iTunes' clips are 30 s).
const double kPreviewSeconds = 30;

class PreviewController extends Notifier<PreviewState> {
  StreamSubscription<Duration>? _pos;
  StreamSubscription<void>? _done;

  @override
  PreviewState build() {
    ref.onDispose(() {
      _pos?.cancel();
      _done?.cancel();
      try {
        ref.read(previewEngineProvider).stop();
      } catch (_) {}
    });
    return const PreviewState();
  }

  /// Tap on a row's play: start it, or stop it when it is the one playing.
  Future<void> toggle(WeeklyPick pick, {bool all = false}) async {
    if (state.playing(pick.id)) return stop();
    final url = pick.previewUrl;
    if (url == null) return;
    if (!await ref.read(previewNetworkOkProvider)()) {
      state = PreviewState(error: 'Previews wait for Wi-Fi. You can change this in Settings › Weekly Exploration.');
      return;
    }
    state = PreviewState(pickId: pick.id, status: PreviewStatus.loading, all: all);
    ref.read(previewProgressProvider.notifier).set(0);
    final engine = ref.read(previewEngineProvider);
    try {
      await ref.read(previewPauseMainProvider)();
      await _pos?.cancel();
      await _done?.cancel();
      await engine.play(url);
      if (state.pickId != pick.id) return; // another tap won while it loaded
      state = PreviewState(pickId: pick.id, status: PreviewStatus.playing, all: all);
      _pos = engine.position.listen((d) {
        if (state.pickId == pick.id) ref.read(previewProgressProvider.notifier).set((d.inMilliseconds / (kPreviewSeconds * 1000)).clamp(0, 1));
      });
      _done = engine.completed.listen((_) => _onDone(pick.id));
    } catch (_) {
      if (state.pickId == pick.id) state = const PreviewState(error: 'That preview couldn’t play. Try again.');
    }
  }

  /// "Play all previews": the first undecided pick with a clip, then the rest as each ends.
  Future<void> playAll() async {
    final list = _undecided();
    _order = [for (final p in list) p.id];
    if (list.isNotEmpty) await toggle(list.first, all: true);
  }

  /// The ids "play all" walks through, fixed when it starts so deciding a song does not reshuffle it.
  List<int> _order = const [];

  List<WeeklyPick> _undecided() {
    final w = ref.read(weeklyExplorationProvider).asData?.value;
    return [for (final p in w?.picks ?? const <WeeklyPick>[]) if (p.isPending && p.previewUrl != null) p];
  }

  Future<void> _onDone(int id) async {
    if (state.pickId != id) return;
    final all = state.all;
    final left = {for (final p in _undecided()) p.id: p};
    final i = _order.indexOf(id);
    final nextId = all && i >= 0 ? _order.skip(i + 1).where(left.containsKey).firstOrNull : null;
    await stop();
    if (nextId != null) await toggle(left[nextId]!, all: true);
  }

  /// A pick was decided while it plays: stop, or carry on to the next in "play all".
  Future<void> decided(int id) async {
    if (state.pickId != id) return;
    await _onDone(id);
  }

  Future<void> stop() async {
    await _pos?.cancel();
    await _done?.cancel();
    _pos = _done = null;
    state = const PreviewState();
    ref.read(previewProgressProvider.notifier).set(0);
    try {
      await ref.read(previewEngineProvider).stop();
    } catch (_) {}
  }
}

final previewControllerProvider = NotifierProvider<PreviewController, PreviewState>(PreviewController.new);
