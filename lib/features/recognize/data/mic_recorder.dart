import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Where the microphone permission stands.
enum MicAccess {
  granted,

  /// Not granted, but the system will still ask.
  denied,

  /// Refused for good: only the system Settings can turn it on.
  blocked,
}

/// The microphone, as the recognition flow needs it. A seam so tests drive
/// the flow without a device.
abstract class MicRecorder {
  /// Current permission; with [request] true, asks the person if still allowed.
  Future<MicAccess> access({required bool request});

  /// Starts recording to a new temporary file and returns its path.
  Future<String> start();

  /// Stops and returns the finished file's path (null if nothing was kept).
  Future<String?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  /// Opens the system page where the permission can be turned on.
  Future<void> openSettings();

  Future<void> dispose();
}

/// [MicRecorder] on the device microphone: 16 kHz mono WAV. That is what
/// the fingerprinter works from anyway (it resamples to 11 kHz), and 12
/// seconds stay around 350 KB.
class DeviceMicRecorder implements MicRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<MicAccess> access({required bool request}) async {
    var status = await Permission.microphone.status;
    if (!status.isGranted && request) {
      status = await Permission.microphone.request();
    }
    if (status.isGranted) return MicAccess.granted;
    if (status.isPermanentlyDenied) return MicAccess.blocked;
    return MicAccess.denied;
  }

  @override
  Future<String> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}recognize_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _path = path;
    return path;
  }

  @override
  Future<String?> stop() async {
    final path = await _recorder.stop();
    _path = null;
    return path;
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
