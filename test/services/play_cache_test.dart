import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/status/logic/status_providers.dart';
import 'package:navivibe/services/play_cache.dart';

class _Net implements HttpClientAdapter {
  final requests = <String>[];
  int size = 1000;
  bool fail = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o.uri.toString());
    if (fail) throw DioException.connectionError(requestOptions: o, reason: 'down');
    return ResponseBody.fromBytes(List.filled(size, 9), 200, headers: {
      'content-type': ['audio/flac'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late _Net net;
  late PlayCache cache;
  var limit = 10 * 1024;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('navi_pc_');
    net = _Net();
    limit = 10 * 1024;
    cache = PlayCache(dir: dir, maxBytes: () => limit, dioFactory: () => Dio()..httpClientAdapter = net);
    await cache.initialize();
  });
  tearDown(() => dir.delete(recursive: true));

  Uri url(String id, {String token = 't1'}) => Uri.parse('https://navi.test/rest/stream.view?id=$id&t=$token');

  group('key stability', () {
    test('the key is song + quality: a new login token or URL does not change it', () {
      final a = cache.fileFor('s1', 'orig')!.path;
      expect(cache.fileFor('s1', 'orig')!.path, a);
      expect(cache.fileFor('s2', 'orig')!.path, isNot(a));
      expect(cache.fileFor('s1', 'mp3-128')!.path, isNot(a));
    });

    test('quality names the transcode; raw or unset means the original', () {
      expect(PlayCache.qualityKey(), 'orig');
      expect(PlayCache.qualityKey(format: 'raw', bitrate: 0), 'orig');
      expect(PlayCache.qualityKey(format: 'mp3', bitrate: 192), 'mp3-192');
      expect(PlayCache.qualityKey(bitrate: 128), 'raw-128');
    });

    test('the same song cached before a restart, under another token, is a hit', () async {
      await cache.prefetch('s1', 'orig', url('s1', token: 'old'));
      final again = PlayCache(dir: dir); // a restart, new token
      await again.initialize();
      expect(await again.completeFile('s1', 'orig'), isNotNull);
    });
  });

  group('previous and replay', () {
    test('a cached song is found with no request, and a miss is null', () async {
      await cache.prefetch('s1', 'orig', url('s1'));
      expect(net.requests, hasLength(1));
      final before = net.requests.length;
      expect(await cache.completeFile('s1', 'orig'), isNotNull); // going back to it
      expect(await cache.completeFile('s1', 'mp3-128'), isNull); // other quality: not the same bytes
      expect(await cache.completeFile('s2', 'orig'), isNull);
      expect(net.requests.length, before);
    });

    test('a song already cached is not downloaded again', () async {
      await cache.prefetch('s1', 'orig', url('s1'));
      await cache.prefetch('s1', 'orig', url('s1'));
      expect(net.requests, hasLength(1));
    });

    test('a finished file carries the type sidecar the streaming source reads', () async {
      await cache.prefetch('s1', 'orig', url('s1'));
      final f = cache.fileFor('s1', 'orig')!;
      expect(File('${f.path}.mime').readAsStringSync(), 'audio/flac');
    });

    test('a failed download leaves nothing behind and never throws', () async {
      net.fail = true;
      await cache.prefetch('s1', 'orig', url('s1'));
      expect(await cache.completeFile('s1', 'orig'), isNull);
      expect(dir.listSync(), isEmpty);
    });
  });

  group('size limit', () {
    Future<void> add(String id, DateTime used) async {
      await cache.prefetch(id, 'orig', url(id));
      await cache.fileFor(id, 'orig')!.setLastModified(used);
    }

    test('the least recently used songs go first', () async {
      net.size = 4000;
      limit = 100 * 1024;
      final now = DateTime.now();
      await add('old', now.subtract(const Duration(hours: 3)));
      await add('mid', now.subtract(const Duration(hours: 2)));
      await add('new', now.subtract(const Duration(hours: 1)));
      limit = 9000; // room for two
      await cache.evict();
      expect(await cache.completeFile('old', 'orig'), isNull);
      expect(await cache.completeFile('mid', 'orig'), isNotNull);
      expect(await cache.completeFile('new', 'orig'), isNotNull);
      expect(File('${cache.fileFor('old', 'orig')!.path}.mime').existsSync(), isFalse);
    });

    test('playing a song again moves it to the back of the line', () async {
      net.size = 4000;
      limit = 100 * 1024;
      final now = DateTime.now();
      await add('a', now.subtract(const Duration(hours: 3)));
      await add('b', now.subtract(const Duration(hours: 2)));
      await cache.completeFile('a', 'orig'); // replayed: now the newest
      limit = 5000;
      await cache.evict();
      expect(await cache.completeFile('b', 'orig'), isNull);
      expect(await cache.completeFile('a', 'orig'), isNotNull);
    });

    test('songs around the one playing are never evicted', () async {
      net.size = 4000;
      limit = 100 * 1024;
      final now = DateTime.now();
      await add('playing', now.subtract(const Duration(hours: 5)));
      await add('other', now.subtract(const Duration(hours: 1)));
      limit = 1000;
      await cache.evict(keep: {'playing'});
      expect(await cache.completeFile('playing', 'orig'), isNotNull);
      expect(await cache.completeFile('other', 'orig'), isNull);
    });

    test('a prefetch that pushes past the limit trims on its own', () async {
      net.size = 6000;
      await cache.prefetch('a', 'orig', url('a'));
      await cache.fileFor('a', 'orig')!.setLastModified(DateTime.now().subtract(const Duration(hours: 1)));
      await cache.prefetch('b', 'orig', url('b')); // 12000 > 10240
      expect(await cache.sizeBytes(), lessThanOrEqualTo(limit + 20)); // .mime sidecar
      expect(await cache.completeFile('b', 'orig'), isNotNull);
    });
  });

  group('clear and size', () {
    test('reports its size and clear empties it', () async {
      await cache.prefetch('a', 'orig', url('a'));
      await cache.prefetch('b', 'orig', url('b'));
      expect(await cache.sizeBytes(), greaterThanOrEqualTo(2000));
      await cache.clear();
      expect(await cache.sizeBytes(), 0);
      expect(await cache.completeFile('a', 'orig'), isNull);
    });

    test('half-written downloads from an old run are swept at start', () async {
      final stale = File('${dir.path}/x.orig.audio.dl')..writeAsBytesSync([1]);
      stale.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
      final fresh = File('${dir.path}/y.orig.audio.part')..writeAsBytesSync([1]);
      await cache.initialize();
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('Status row words the size against the limit', () {
      expect(describePlayCache(0, limitBytes: 500 * 1024 * 1024).detail, 'Empty');
      expect(describePlayCache(120 * 1024 * 1024, limitBytes: 500 * 1024 * 1024).detail, '120 MB of 500 MB');
    });
  });
}
