import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/keyringless_key.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/services/linux_connectivity.dart';
import 'package:navivibe/services/linux_shutdown.dart';
import 'package:navivibe/utils/desktop_share.dart';

class _NoNetworkManager extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => throw const SocketException('no system bus');
}

/// Like the real one with no system bus: the call fails, and a second error
/// escapes from work nobody awaits.
class _StrayError extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    scheduleMicrotask(() => throw const SocketException('no system bus (signal subscription)'));
    await Future<void>.delayed(Duration.zero);
    throw const SocketException('no system bus');
  }
}

class _Works extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => const [ConnectivityResult.wifi];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('navi_linux_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('key file (no keyring)', () {
    test('is created once and read back', () async {
      final first = await readOrCreateKeyFile(tmp);
      expect(first, hasLength(32));
      expect(await readOrCreateKeyFile(tmp), first);
    });

    test('a damaged file is replaced', () async {
      File('${tmp.path}/auth.key').writeAsStringSync('not base64!');
      final key = await readOrCreateKeyFile(tmp);
      expect(key, hasLength(32));
      expect(await readOrCreateKeyFile(tmp), key);
    });
  });

  group('connectivity without NetworkManager', () {
    late ConnectivityPlatform original;
    setUp(() => original = ConnectivityPlatform.instance);
    tearDown(() => ConnectivityPlatform.instance = original);

    test('assumes online', () async {
      ConnectivityPlatform.instance = _NoNetworkManager();
      await installLinuxConnectivityFallback();
      expect(await ConnectivityPlatform.instance.checkConnectivity(), [ConnectivityResult.other]);
    });

    test('keeps a stray error from the client to itself', () async {
      ConnectivityPlatform.instance = _StrayError();
      // An escaped error would fail this test.
      await installLinuxConnectivityFallback();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ConnectivityPlatform.instance, isA<AssumeOnlineConnectivity>());
    });

    test('leaves a working implementation alone', () async {
      final works = _Works();
      ConnectivityPlatform.instance = works;
      await installLinuxConnectivityFallback();
      expect(ConnectivityPlatform.instance, same(works));
    });
  });

  test('a file the app was opened with survives the library loading afterwards', () {
    final index = LocalLibraryIndex.instance..clear();
    addTearDown(index.clear);
    index.register('local:opened', '/music/opened.flac');
    index.replace(paths: const {}, covers: const {});
    expect(index.pathFor('local:opened'), '/music/opened.flac');
    index.replace(paths: const {'local:opened': '/library/opened.flac'}, covers: const {});
    expect(index.pathFor('local:opened'), '/library/opened.flac');
  });

  group('quitting', () {
    test('runs every step in order, then exits once, even when one fails or hangs', () async {
      final ran = <String>[];
      final codes = <int>[];
      final shutdown = LinuxShutdown([
        () async => ran.add('save'),
        () async => throw StateError('broken step'),
        () => Completer<void>().future, // never finishes
        () async => ran.add('close database'),
      ], stepTimeout: const Duration(milliseconds: 20), quit: codes.add);

      final first = shutdown.run();
      await shutdown.run(); // a second click on the close button
      await first;

      expect(ran, ['save', 'close database']);
      expect(codes, [0]);
    });
  });

  group('sharing by copying', () {
    String? copied;
    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
    });

    test('text goes to the clipboard', () async {
      expect(await shareByCopying('hello'), 'Copied. Paste it into a message.');
      expect(copied, 'hello');
    });

    test('a picture is saved to Downloads', () async {
      final card = File('${tmp.path}/card.png')..writeAsBytesSync([1, 2, 3]);
      final downloads = Directory('${tmp.path}/Downloads');
      expect(await shareByCopying('hi', file: card, downloads: () async => downloads),
          'Picture saved to Downloads, text copied.');
      expect(File('${downloads.path}/card.png').readAsBytesSync(), [1, 2, 3]);
    });

    test('says so when there is no Downloads folder', () async {
      final card = File('${tmp.path}/card.png')..writeAsBytesSync([1]);
      expect(await shareByCopying('hi', file: card, downloads: () async => null),
          'Text copied. The picture couldn’t be saved.');
    });
  });
}
