import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/web_storage_stub.dart' as storage_stub;
import 'package:navivibe/services/windows_smtc.dart';
import 'package:navivibe/services/windows_smtc_sink_stub.dart' as smtc_stub;
import 'package:navivibe/utils/web_env_stub.dart' as env_stub;
import 'package:navivibe/features/updates/logic/update_providers.dart' show updatesSupported;
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/utils/platform_utils.dart';

// The browser build swaps these files in through conditional imports. They are
// plain Dart, so the VM can check they behave as no-ops.
void main() {
  test('SMTC sink stub: no SMTC in a browser, every call is a no-op', () async {
    expect(await smtc_stub.SmtcWindowsSink.create(), isNull);
    final sink = smtc_stub.SmtcWindowsSink();
    expect(await sink.buttons.isEmpty, isTrue);
    await sink.setTrack(const SmtcTrack(title: 't', artist: 'a', album: 'b'));
    await sink.setStatus(SmtcStatus.playing);
    await sink.setTimeline(position: Duration.zero, duration: const Duration(seconds: 3));
    await sink.dispose();
  });

  test('SMTC on a native host still exports the plugin-backed sink', () async {
    // Not Windows (CI) -> null without touching the plugin; on Windows the
    // real class is exported (the stub would also return null, so check type).
    final sink = await SmtcWindowsSink.create();
    if (!PlatformUtils.isWindows) expect(sink, isNull);
    expect(SmtcWindowsSink, isNot(smtc_stub.SmtcWindowsSink));
  });

  test('web storage stub stores nothing', () {
    const s = storage_stub.WebStorage();
    s.write('k', 'v');
    expect(s.read('k'), isNull);
    s.remove('k');
  });

  test('browser info stub reports "not a browser"', () {
    expect(env_stub.readBrowserInfo(), isNull);
  });

  test('native-only shells stay native-only', () {
    // Window/tray/mini-player features never turn on because a desktop layout
    // is showing; they follow the OS.
    expect(MiniPlayer.supported, PlatformUtils.isNativeDesktop);
    expect(PlatformUtils.supportsWindowManager, PlatformUtils.isNativeDesktop);
    expect(updatesSupported, PlatformUtils.isAndroid || PlatformUtils.isWindows);
  });
}
