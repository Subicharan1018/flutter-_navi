import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/local_library/logic/download_location.dart';
import 'package:navivibe/offline_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore extends DownloadLocationStore {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String? path) async => value = path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late Directory elsewhere;
  late _MemoryStore store;
  final offline = OfflineService();
  final sep = Platform.pathSeparator;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('navi_docs_');
    elsewhere = await Directory.systemTemp.createTemp('navi_other_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    store = _MemoryStore();
    offline
      ..resetForTest()
      ..useLocationStore(store);
  });

  tearDown(() async {
    offline.useLocationStore(const DownloadLocationStore());
    offline.resetForTest();
    await docs.delete(recursive: true);
    await elsewhere.delete(recursive: true);
  });

  test('uses app storage until a folder is chosen', () async {
    await offline.initialize();
    expect(offline.downloadsDirectory, '${docs.path}${sep}offline_music');
  });

  test('a chosen folder is used on the next start', () async {
    store.value = elsewhere.path;
    await offline.initialize();
    expect(offline.downloadsDirectory, '${elsewhere.path}$sep$downloadsFolderName');
    expect(Directory(offline.downloadsDirectory!).existsSync(), isTrue);
  });

  test('a chosen folder that has gone falls back to app storage', () async {
    store.value = '${elsewhere.path}${sep}vanished${sep}deeper';
    await File('${elsewhere.path}${sep}vanished').writeAsString('a file where a folder should be');
    await offline.initialize();
    expect(offline.downloadsDirectory, '${docs.path}${sep}offline_music');
  });

  test('changing the location moves the downloaded files and remembers it', () async {
    await offline.initialize();
    final old = Directory(offline.downloadsDirectory!);
    await File('${old.path}${sep}s1.mp3').writeAsBytes([1, 2, 3]);
    await File('${old.path}${sep}s1.song.json').writeAsString('{}');
    await offline.initialize();

    final progress = <int>[];
    final error = await offline.setDownloadLocation(
      elsewhere.path,
      moveExisting: true,
      onProgress: (d, _) => progress.add(d),
    );

    expect(error, isNull);
    expect(store.value, elsewhere.path);
    expect(offline.downloadsDirectory, '${elsewhere.path}$sep$downloadsFolderName');
    expect(old.listSync(), isEmpty);
    expect(offline.getLocalPath('s1'), '${offline.downloadsDirectory}/s1.mp3');
    expect(progress, isNotEmpty);
  });

  test('without moving, old files stay and the setting still changes', () async {
    await offline.initialize();
    final old = Directory(offline.downloadsDirectory!);
    await File('${old.path}${sep}s1.mp3').writeAsBytes([1]);

    expect(await offline.setDownloadLocation(elsewhere.path), isNull);
    expect(old.listSync(), hasLength(1));
    expect(offline.getLocalPath('s1'), isNull);

    // And back to app storage: the old files are found again.
    expect(await offline.setDownloadLocation(null), isNull);
    expect(store.value, isNull);
    expect(offline.getLocalPath('s1'), isNotNull);
  });

  test('a folder that cannot be written is refused and nothing changes', () async {
    await offline.initialize();
    final before = offline.downloadsDirectory;
    final blocker = File('${elsewhere.path}${sep}blocker')..writeAsStringSync('x');
    final error = await offline.setDownloadLocation(blocker.path);
    expect(error, isNotNull);
    expect(store.value, isNull);
    expect(offline.downloadsDirectory, before);
  });
}
