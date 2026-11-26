/// Where the equalizer actually runs. Each engine is handed the six band gains,
/// or null for "bypass", and bypass means nothing is left in the audio path.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../logic/eq_model.dart';
import '../logic/mpv_filter.dart';

abstract class EqEngine {
  /// Applies [gains], or removes the equalizer when null. Throws when the
  /// platform refused, so the caller can retry later.
  Future<void> apply(List<double>? gains);

  /// Volume factor (≤ 1) the player has to apply for headroom. 1 where the
  /// engine does that itself.
  double get headroom => 1;

  /// Called when the audio output was re-created and the effect must be
  /// attached again.
  set onOutputChanged(VoidCallback callback) {}

  void dispose() {}
}

/// Android and Android TV: a `DynamicsProcessing` effect (Android 9+; the
/// older `Equalizer` effect below that) on the player's own audio session.
/// See EqChannel.kt.
class AndroidEqEngine extends EqEngine {
  static const _channel = MethodChannel('com.navivibe/equalizer');
  final AudioPlayer _player;
  StreamSubscription<int?>? _sessionSub;
  int? _sessionId;
  VoidCallback? _onOutputChanged;
  bool _attached = false;

  AndroidEqEngine(this._player) {
    _sessionSub = _player.androidAudioSessionIdStream.listen((id) {
      if (id == _sessionId) return;
      _sessionId = id;
      _onOutputChanged?.call();
    });
  }

  @override
  set onOutputChanged(VoidCallback callback) => _onOutputChanged = callback;

  @override
  Future<void> apply(List<double>? gains) async {
    final session = _sessionId ?? _player.androidAudioSessionId;
    // Session 0 is the whole phone's output: never attach there.
    if (gains == null || session == null || session == 0) {
      if (!_attached) return;
      await _channel.invokeMethod<void>('release');
      _attached = false;
      return;
    }
    final slices = eqSlices(gains);
    final engine = await _channel.invokeMethod<String>('apply', {
      'sessionId': session,
      'cutoffs': [for (final s in slices) s.cutoffHz],
      'gains': [for (final s in slices) s.gainDb],
      'inputGain': headroomDb(slices.map((s) => s.gainDb)),
    });
    _attached = true;
    debugPrint('🎚️ [Equalizer] $engine on session $session');
  }

  @override
  void dispose() {
    unawaited(_sessionSub?.cancel());
    unawaited(apply(null).catchError((_) {}));
  }
}

/// Windows and Linux: FFmpeg peaking filters inside mpv.
class MpvEqEngine extends EqEngine {
  double _headroom = 1;

  @override
  double get headroom => _headroom;

  @override
  Future<void> apply(List<double>? gains) async {
    final eq = gains == null ? MpvEq.off : mpvEqFor(gains);
    await JustAudioMediaKit.setAudioFilter(eq.filter);
    _headroom = eq.headroom;
  }
}
