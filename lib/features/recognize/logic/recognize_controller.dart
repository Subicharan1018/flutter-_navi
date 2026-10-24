import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/services/shuffle_api_service.dart';
import '../data/mic_recorder.dart';
import '../data/recognize_api.dart';
import '../data/recognize_models.dart';

final recognizeApiProvider = Provider<RecognizeApi>((ref) {
  return RecognizeApi(
    createShuffleDio(() {
      final s = ref.read(settingsProvider);
      return (s.username, s.password);
    }, logTag: 'Recognize'),
  );
});

/// The microphone. Overridden in tests.
final micRecorderProvider = Provider<MicRecorder>((ref) {
  final recorder = DeviceMicRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

enum RecognizePhase {
  idle,

  /// The system will ask for the microphone when the person agrees.
  needsPermission,

  /// Permission was refused for good; Settings is the only way back.
  blocked,
  listening,
  identifying,
  found,
  notFound,
  failed,
}

class RecognizeState {
  final RecognizePhase phase;
  final RecognizeResult? result;
  final String? message;

  const RecognizeState(this.phase, {this.result, this.message});
}

/// Listen for ~11 seconds, send the clip to the server, show what it found.
/// autoDispose: closing the sheet stops the microphone and drops the clip.
class RecognizeController extends Notifier<RecognizeState> {
  @visibleForTesting
  static Duration listenFor = const Duration(seconds: 11);

  Timer? _timer;
  int _generation = 0;

  @override
  RecognizeState build() {
    final mic = ref.read(micRecorderProvider);
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      // Frees the microphone and drops the clip if one was recording.
      unawaited(mic.cancel());
    });
    return const RecognizeState(RecognizePhase.idle);
  }

  MicRecorder get _mic => ref.read(micRecorderProvider);

  /// Starts listening, asking for the microphone first if needed.
  Future<void> start() async {
    if (state.phase == RecognizePhase.listening ||
        state.phase == RecognizePhase.identifying) {
      return;
    }
    final gen = ++_generation;
    final access = await _mic.access(request: true);
    if (!ref.mounted || gen != _generation) return;
    switch (access) {
      case MicAccess.denied:
        state = const RecognizeState(RecognizePhase.needsPermission);
        return;
      case MicAccess.blocked:
        state = const RecognizeState(RecognizePhase.blocked);
        return;
      case MicAccess.granted:
        break;
    }
    try {
      await _mic.start();
    } catch (e) {
      debugPrint('[Recognize] could not start recording: $e');
      if (ref.mounted && gen == _generation) {
        state = const RecognizeState(
          RecognizePhase.failed,
          message: 'Couldn’t use the microphone.',
        );
      }
      return;
    }
    if (!ref.mounted || gen != _generation) {
      unawaited(_mic.cancel());
      return;
    }
    state = const RecognizeState(RecognizePhase.listening);
    _timer = Timer(listenFor, () => _identify(gen));
  }

  Future<void> _identify(int gen) async {
    if (!ref.mounted || gen != _generation) return;
    state = const RecognizeState(RecognizePhase.identifying);
    String? path;
    try {
      path = await _mic.stop();
      if (path == null) {
        throw const RecognizeException('Nothing was recorded. Try again.');
      }
      final result = await ref.read(recognizeApiProvider).recognize(path);
      if (!ref.mounted || gen != _generation) return;
      state = RecognizeState(
        result.recognized ? RecognizePhase.found : RecognizePhase.notFound,
        result: result,
      );
    } on RecognizeException catch (e) {
      if (ref.mounted && gen == _generation) {
        state = RecognizeState(RecognizePhase.failed, message: e.message);
      }
    } catch (e) {
      debugPrint('[Recognize] $e');
      if (ref.mounted && gen == _generation) {
        state = const RecognizeState(
          RecognizePhase.failed,
          message: 'Couldn’t identify that. Try again.',
        );
      }
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  /// Stops listening and forgets the clip.
  Future<void> cancel() async {
    _generation++;
    _timer?.cancel();
    await _mic.cancel();
    if (ref.mounted) state = const RecognizeState(RecognizePhase.idle);
  }

  Future<void> openSettings() => _mic.openSettings();
}

final recognizeProvider =
    NotifierProvider.autoDispose<RecognizeController, RecognizeState>(
      RecognizeController.new,
    );

/// The library song behind a recognised track, by id. Fetched with the
/// song's own metadata (it's already in the library, so no mirroring).
final recognizedSongProvider = FutureProvider.autoDispose.family<Song, String>((
  ref,
  id,
) {
  return ref.read(subsonicServiceProvider).getSong(id);
});
