// Head start: the first bytes of the next songs are kept ahead of time, and a
// skip onto one plays from them while the rest downloads (one request, not two).
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/play_cache.dart';

/// A server with one 3 MB song that answers byte ranges (or ignores them).
class _Server implements HttpClientAdapter {
  _Server({this.ranges = true});
  final bool ranges;
  static const int size = 3 * 1024 * 1024;
  final data = Uint8List.fromList(List.generate(size, (i) => i % 251));
  final requests = <String?>[]; // the Range header of each request

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final range = o.headers['Range'] as String?;
    requests.add(range);
    if (range == null || !ranges) {
      return ResponseBody.fromBytes(data, 200, headers: {
        'content-type': ['audio/flac'],
      });
    }
    final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    final end = m.group(2)!.isEmpty ? size - 1 : int.parse(m.group(2)!);
    return ResponseBody.fromBytes(data.sublist(start, end + 1), 206, headers: {
      'content-type': ['audio/flac'],
      'content-range': ['bytes $start-$end/$size'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late _Server net;
  late PlayCache cache;
  final url = Uri.parse('https://navi.test/rest/stream.view?id=s1');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('navi_head_');
    net = _Server();
    cache = PlayCache(dir: dir, dioFactory: () => Dio()..httpClientAdapter = net);
    await cache.initialize();
  });
  tearDown(() => dir.delete(recursive: true));

  test('keeps the first bytes and the song size', () async {
    await cache.prefetchHead('s1', 'orig', url);
    final h = cache.headSync('s1', 'orig')!;
    expect(h.length, PlayCache.headBytes);
    expect(h.total, _Server.size);
    expect(h.mime, contains('flac'));
    expect(listEquals(h.file.readAsBytesSync(), net.data.sublist(0, PlayCache.headBytes)), isTrue);
    expect(net.requests, ['bytes=0-${PlayCache.headBytes - 1}']);
  });

  test('a server that ignores ranges keeps nothing (it would send the whole song)', () async {
    net = _Server(ranges: false);
    cache = PlayCache(dir: dir, dioFactory: () => Dio()..httpClientAdapter = net);
    await cache.prefetchHead('s1', 'orig', url);
    expect(cache.headSync('s1', 'orig'), isNull);
  });

  test('a song already on disk, or with a head, is not asked for again', () async {
    await cache.prefetchHead('s1', 'orig', url);
    await cache.prefetchHead('s1', 'orig', url);
    expect(net.requests, hasLength(1));
    await cache.prefetch('s2', 'orig', url);
    net.requests.clear();
    await cache.prefetchHead('s2', 'orig', url);
    expect(net.requests, isEmpty);
  });

  test('playing from the head asks the server for the rest only, and ends with a finished song', () async {
    await cache.prefetchHead('s1', 'orig', url);
    net.requests.clear();
    final h = cache.headSync('s1', 'orig')!;
    final out = BytesBuilder();
    await for (final chunk in cache.readThrough('s1', 'orig', url, start: 0, end: h.total, total: h.total)) {
      out.add(chunk);
    }
    expect(listEquals(out.takeBytes(), net.data), isTrue, reason: 'head then rest, byte for byte');
    expect(net.requests, ['bytes=${PlayCache.headBytes}-'], reason: 'one request, for the rest');
    // The download carries on until the song is on disk.
    for (var i = 0; i < 250 && await cache.completeFile('s1', 'orig') == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await cache.completeFile('s1', 'orig'), isNotNull);
    expect(listEquals(cache.fileFor('s1', 'orig')!.readAsBytesSync(), net.data), isTrue);
    expect(cache.headSync('s1', 'orig'), isNull, reason: 'the stand-in is dropped once the song is whole');
  });

  test('a seek into the part not yet downloaded is served by a range request', () async {
    await cache.prefetchHead('s1', 'orig', url);
    final h = cache.headSync('s1', 'orig')!;
    final start = h.total - 1000;
    final out = BytesBuilder();
    await for (final chunk in cache.readThrough('s1', 'orig', url, start: start, end: h.total, total: h.total)) {
      out.add(chunk);
    }
    expect(listEquals(out.takeBytes(), net.data.sublist(start)), isTrue);
  });
}
