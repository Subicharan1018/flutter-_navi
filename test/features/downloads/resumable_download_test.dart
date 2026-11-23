import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_utils.dart';

/// A server for one file: honours `Range` unless [ignoreRange], and can cut the
/// body short ([cutAfter] bytes) like a dropped connection.
class _Server implements HttpClientAdapter {
  _Server(this.body);
  final List<int> body;
  bool ignoreRange = false;
  int? cutAfter;
  final List<String?> ranges = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final range = options.headers['range'] as String?;
    ranges.add(range);
    var from = 0;
    var status = 200;
    if (range != null && !ignoreRange) {
      from = int.parse(range.substring('bytes='.length).replaceAll('-', ''));
      if (from >= body.length) return ResponseBody.fromBytes(const [], 416);
      status = 206;
    }
    final slice = body.sublist(from);
    final headers = {
      Headers.contentLengthHeader: ['${slice.length}'],
    };
    final cut = cutAfter;
    if (cut != null && cut < slice.length) {
      final stream = Stream<Uint8List>.fromIterable([Uint8List.fromList(slice.sublist(0, cut))])
          .asyncExpand((c) async* {
        yield c;
        throw const SocketException('connection lost');
      });
      return ResponseBody(stream, status, headers: headers);
    }
    return ResponseBody.fromBytes(slice, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late _Server server;
  late String target;
  final offline = OfflineService();
  final bytes = List<int>.generate(1000, (i) => i % 251);

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('navi_resume_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    server = _Server(bytes);
    offline
      ..resetForTest()
      ..dioFactory = (() => Dio()..httpClientAdapter = server);
    await offline.initialize();
    target = '${offline.downloadsDirectory}/s1.mp3';
  });

  tearDown(() async {
    offline.dioFactory = Dio.new;
    offline.resetForTest();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      await docs.delete(recursive: true);
    } catch (_) {}
  });

  test('a finished download appears under its final name only, with every byte', () async {
    final progress = <double>[];
    await offline.fetchResumable('http://x/s1', target, onProgress: progress.add);
    expect(File(target).readAsBytesSync(), bytes);
    expect(File('$target.part').existsSync(), isFalse);
    expect(progress.last, 1.0);
  });

  test('a dropped connection leaves a partial file, never a song, and the next try resumes it', () async {
    server.cutAfter = 400;
    await expectLater(offline.fetchResumable('http://x/s1', target), throwsA(anything));
    expect(File(target).existsSync(), isFalse, reason: 'half a song must not count as downloaded');
    expect(File('$target.part').lengthSync(), 400);

    server.cutAfter = null;
    await offline.fetchResumable('http://x/s1', target);
    expect(server.ranges.last, 'bytes=400-');
    expect(File(target).readAsBytesSync(), bytes);
    expect(File('$target.part').existsSync(), isFalse);
  });

  test('a server that ignores Range sends the whole file again, which replaces the partial', () async {
    File('$target.part').writeAsBytesSync(List.filled(300, 9));
    server.ignoreRange = true;
    await offline.fetchResumable('http://x/s1', target);
    expect(File(target).readAsBytesSync(), bytes);
  });

  test('a partial file that no longer fits the server (416) restarts cleanly', () async {
    File('$target.part').writeAsBytesSync(List.filled(5000, 9)); // longer than the file
    await offline.fetchResumable('http://x/s1', target);
    expect(File(target).readAsBytesSync(), bytes);
  });

  test('a body that ends early without an error is not accepted', () async {
    final short = _ShortServer(bytes);
    offline.dioFactory = () => Dio()..httpClientAdapter = short;
    await expectLater(offline.fetchResumable('http://x/s1', target), throwsA(isA<DioException>()));
    expect(File(target).existsSync(), isFalse);
    expect(File('$target.part').lengthSync(), 500);
  });

  test('cancelling removes the partial file and reports failure', () async {
    final slow = _SlowServer(bytes);
    offline.dioFactory = () => Dio()..httpClientAdapter = slow;
    final song = _song();
    final svc = _Svc();
    final f = offline.downloadSong(song, svc);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    offline.cancelDownload(song.id);
    slow.release();
    expect(await f, isFalse);
    expect(File('${offline.downloadsDirectory}/s1.mp3.part').existsSync(), isFalse);
    expect(offline.isSongDownloaded('s1'), isFalse);
  });
}

Song _song() => makeSong(id: 's1', title: 'T');

class _Svc extends Fake implements SubsonicService {
  @override
  String getStreamUrl(String id, {int? maxBitRate, String? format}) => 'http://x/s1';
  @override
  String getRemoteCoverArtUrl(String? id, {int? size}) => '';
  @override
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async => null;
  @override
  Future<String?> getLyrics({String? artist, String? title}) async => null;
}

/// Declares 1000 bytes, sends 500, and ends the stream normally.
class _ShortServer extends _Server {
  _ShortServer(super.body);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody(
      Stream.value(Uint8List.fromList(body.sublist(0, 500))),
      200,
      headers: {
        Headers.contentLengthHeader: ['${body.length}'],
      },
    );
  }
}

/// Sends the first half, then waits until released.
class _SlowServer extends _Server {
  _SlowServer(super.body);
  final _gate = Completer<void>();
  void release() => _gate.complete();
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Stream<Uint8List> gen() async* {
      yield Uint8List.fromList(body.sublist(0, 400));
      await _gate.future;
      yield Uint8List.fromList(body.sublist(400));
    }

    return ResponseBody(gen(), 200, headers: {
      Headers.contentLengthHeader: ['${body.length}'],
    });
  }
}
