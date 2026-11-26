import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../providers/player_provider.dart';

/// Makes the sound of one 30 s preview. Its own player instance (never the library queue's), and a volume so one clip can
/// fade out as the next fades in.
abstract class FeedAudio {
  /// How far into the clip, about five times a second.
  Stream<Duration> get position;

  /// Fires once when the clip reaches its end.
  Stream<void> get completed;

  /// Loads [url] and starts it. Throws when it cannot.
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double v);
  Future<void> dispose();
}

class JustAudioFeedAudio implements FeedAudio {
  AudioPlayer? _p;
  AudioPlayer get _player => _p ??= AudioPlayer();

  @override
  Stream<Duration> get position => _player.createPositionStream(
    minPeriod: const Duration(milliseconds: 200),
  );

  @override
  Stream<void> get completed => _player.processingStateStream.where(
    (s) => s == ProcessingState.completed,
  );

  @override
  Future<void> play(String url) async {
    await _player.setUrl(url);
    unawaited(_player.play());
  }

  @override
  Future<void> pause() async => _p?.pause();

  @override
  Future<void> resume() async => _p?.play();

  @override
  Future<void> stop() async => _p?.stop();

  @override
  Future<void> setVolume(double v) async => _p?.setVolume(v.clamp(0.0, 1.0));

  @override
  Future<void> dispose() async {
    await _p?.dispose();
    _p = null;
  }
}

final feedAudioProvider = Provider.autoDispose<FeedAudio>((ref) {
  final a = JustAudioFeedAudio();
  ref.onDispose(a.dispose);
  return a;
});

/// The listener's own music, handled politely: pause it when the feed opens (only if it is playing), give it back when the
/// feed closes. Overridden in tests.
class MainPlayerYield {
  const MainPlayerYield({required this.pauseIfPlaying, required this.resume});

  /// Pauses the main player; true when it was playing (so [resume] is owed).
  final Future<bool> Function() pauseIfPlaying;
  final Future<void> Function() resume;
}

final mainPlayerYieldProvider = Provider<MainPlayerYield>(
  (ref) => MainPlayerYield(
    pauseIfPlaying: () async {
      try {
        if (!ref.read(playerProvider).isPlaying) return false;
        await ref.read(playerProvider.notifier).pause();
        return true;
      } catch (_) {
        return false;
      }
    },
    resume: () async {
      try {
        await ref.read(playerProvider.notifier).play();
      } catch (_) {}
    },
  ),
);

/// Fades [audio] between volumes in a few steps (a volume ramp is cheap and needs no second player).
Future<void> fadeVolume(
  FeedAudio audio,
  double from,
  double to,
  Duration over, {
  int steps = 6,
}) async {
  if (over == Duration.zero) return audio.setVolume(to);
  final step = Duration(microseconds: over.inMicroseconds ~/ steps);
  for (var i = 1; i <= steps; i++) {
    await audio.setVolume(from + (to - from) * i / steps);
    await Future<void>.delayed(step);
  }
}
