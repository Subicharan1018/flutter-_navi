import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import '../utils/platform_utils.dart';

// =============================================================================
// voice_input.dart — speech to text for search fields, on phones, Android TV
// and desktop. One engine, one place that knows about the plugin, so widgets
// and tests talk to [VoiceEngine] and never to speech_to_text directly.
// =============================================================================

enum VoiceFailure {
  /// No recognizer on this device (common on bare Android TV boxes).
  unavailable,

  /// The microphone permission was refused.
  denied,

  /// The recognizer started and then reported an error.
  error,
}

abstract class VoiceEngine {
  /// Platforms where it is worth showing a microphone at all.
  bool get supportedPlatform;

  bool get listening;

  /// Starts listening. [onText] gets partial and final transcripts; [onDone]
  /// fires once when listening ends, with the failure if there was one.
  /// Returns false (after calling [onDone]) when it could not start.
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceFailure? failure) onDone,
  });

  Future<void> stop();
}

class SpeechToTextEngine implements VoiceEngine {
  final SpeechToText _stt = SpeechToText();
  bool _initialised = false;
  void Function(VoiceFailure? failure)? _done;
  VoiceFailure? _failure;

  @override
  bool get supportedPlatform =>
      PlatformUtils.isAndroid || PlatformUtils.isIOS || PlatformUtils.isWindows || PlatformUtils.isMacOS;

  @override
  bool get listening => _stt.isListening;

  void _finish() {
    final done = _done;
    _done = null;
    done?.call(_failure);
    _failure = null;
  }

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(VoiceFailure? failure) onDone,
  }) async {
    _done = onDone;
    _failure = null;
    try {
      if (!_initialised) {
        _initialised = await _stt.initialize(
          onError: (e) {
            _failure = e.errorMsg.contains('permission') ? VoiceFailure.denied : VoiceFailure.error;
            // error_no_match / error_speech_timeout just mean "heard nothing".
            if (e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout') _failure = null;
            if (_stt.isListening) return;
            _finish();
          },
          onStatus: (s) {
            if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _finish();
          },
        );
      }
      if (!_initialised) {
        _failure = _stt.hasError ? VoiceFailure.denied : VoiceFailure.unavailable;
        _finish();
        return false;
      }
      await _stt.listen(
        onResult: (r) => onText(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.search,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 20),
        ),
      );
      return true;
    } catch (_) {
      _failure = VoiceFailure.unavailable;
      _finish();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}

/// The engine the app uses; tests swap it for a fake.
abstract final class VoiceInput {
  static VoiceEngine engine = SpeechToTextEngine();
}
