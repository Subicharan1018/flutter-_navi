import 'windows_smtc.dart';

/// Browser build: there is no Windows SMTC. Media keys and the lock screen go
/// through the Media Session API instead (audio_service's web backend).
class SmtcWindowsSink implements SmtcSink {
  static Future<SmtcWindowsSink?> create() async => null;

  @override
  Stream<SmtcButton> get buttons => const Stream.empty();
  @override
  Future<void> setTrack(SmtcTrack? track) async {}
  @override
  Future<void> setStatus(SmtcStatus status) async {}
  @override
  Future<void> setTimeline({required Duration position, required Duration duration}) async {}
  @override
  Future<void> dispose() async {}
}
