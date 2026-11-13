import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/models/library_sort.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/providers/downloaded_songs.dart';
import 'package:navivibe/services/playlist_cache_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request from a table of path → bytes; others fail like a
/// dead network.
class _FakeNet implements HttpClientAdapter {
  final Map<String, List<List<int>>> answers = {}; // path → one answer per request
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = options.uri.path;
    requested.add(key);
    final queue = answers[key];
    if (queue == null || queue.isEmpty) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final bytes = queue.length > 1 ? queue.removeAt(0) : queue.first;
    if (bytes.isEmpty) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

class _Svc extends Fake implements SubsonicService {
  @override
  String getStreamUrl(String id, {int? maxBitRate, String? format}) => 'http://x/rest/stream.view?id=$id';
  @override
  String getRemoteCoverArtUrl(String? id, {int? size}) => id == null || id.isEmpty ? '' : 'http://x/rest/getCoverArt.view?id=$id';
  @override
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async => null;
  @override
  Future<String?> getLyrics({String? artist, String? title}) async => null;
}

final _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

Song _song(String id, {String? cover}) => Song(
      id: id, title: 'T$id', artist: 'A', album: 'Al', coverArt: cover ?? id,
      duration: 100, track: 1, year: 2020, suffix: 'mp3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late _FakeNet net;
  final offline = OfflineService();

  setUpAll(() async {
    final hive = await Directory.systemTemp.createTemp('navi_hive_');
    Hive.init(hive.path);
    HiveBoxes.auth = await Hive.openBox('auth_dl_test');
    HiveBoxes.prefs = await Hive.openBox('prefs_dl_test');
  });

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('navi_dl_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    net = _FakeNet()
      ..answers['/rest/stream.view'] = [List.filled(64, 7)];
    offline
      ..resetForTest()
      ..dioFactory = (() => Dio()..httpClientAdapter = net);
    await offline.initialize();
    LocalLibraryIndex.instance.clear();
  });

  tearDown(() async {
    offline.dioFactory = Dio.new;
    offline.resetForTest();
    LocalLibraryIndex.instance.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100)); // background cover indexing
    try {
      await docs.delete(recursive: true);
    } catch (_) {}
  });

  test('a download saves <id>.jpg and the tile can find it', () async {
    net.answers['/rest/getCoverArt.view'] = [_jpeg];
    expect(await offline.downloadSong(_song('s1'), _Svc()), isTrue);
    final path = offline.getLocalCoverArtPath('s1');
    expect(path, isNotNull);
    expect(File(path!).readAsBytesSync(), _jpeg);
  });

  test('a failed cover fetch is retried once, then leaves no file and a gap to backfill', () async {
    // First request fails, second succeeds: the retry saves it.
    net.answers['/rest/getCoverArt.view'] = [<int>[], _jpeg];
    await offline.downloadSong(_song('s1'), _Svc());
    expect(offline.getLocalCoverArtPath('s1'), isNotNull);

    // Both tries fail: the download still succeeds, with no cover file.
    net.answers['/rest/getCoverArt.view'] = [<int>[]];
    net.answers['/rest/stream.view'] = [List.filled(64, 7)];
    expect(await offline.downloadSong(_song('s2'), _Svc()), isTrue);
    expect(offline.getLocalCoverArtPath('s2'), isNull);
    expect(offline.idsMissingCover(), ['s2']);

    // Back online: the backfill creates it.
    net.answers['/rest/getCoverArt.view'] = [_jpeg];
    expect(await offline.backfillMissingCovers(_Svc()), 1);
    expect(offline.getLocalCoverArtPath('s2'), isNotNull);
    expect(offline.idsMissingCover(), isEmpty);
  });

  test('bytes that are not an image are never kept as the cover', () async {
    net.answers['/rest/getCoverArt.view'] = [utf8.encode('<html>error page, not a picture</html>')];
    await offline.downloadSong(_song('s1'), _Svc());
    expect(offline.getLocalCoverArtPath('s1'), isNull);
    expect(File('${offline.downloadsDirectory}/s1.jpg.part').existsSync(), isFalse);
  });

  test('a song saved with an album cover id is found by that id', () async {
    net.answers['/rest/getCoverArt.view'] = [_jpeg];
    await offline.downloadSong(_song('s1', cover: 'al-9'), _Svc());
    expect(offline.getLocalCoverForCoverId('al-9'), offline.getLocalCoverArtPath('s1'));
    // After a restart the link is rebuilt from the saved metadata.
    offline.resetForTest();
    await offline.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(offline.getLocalCoverForCoverId('al-9'), isNotNull);
  });

  test('remapSongIds carries the cover file to the new id', () async {
    net.answers['/rest/getCoverArt.view'] = [_jpeg];
    await offline.downloadSong(_song('old'), _Svc());
    await offline.remapSongIds({'old': 'new'});
    expect(offline.getLocalCoverArtPath('new'), isNotNull);
    expect(offline.getLocalCoverArtPath('old'), isNull);
  });

  group('cover resolution (getCoverArtUrl)', () {
    test('precedence: downloaded file, then device-library cover, then the network', () async {
      final svc = SubsonicService(
        serverUrl: 'https://navi.test',
        username: 'u',
        password: 'p',
        cache: _NoCache(),
      );
      // Nothing saved: the server link.
      expect(svc.getCoverArtUrl('s1'), contains('getCoverArt'));

      // A matched device song: covers are keyed by its server id too.
      final localCover = File('${docs.path}/local.jpg')..writeAsBytesSync(_jpeg);
      LocalLibraryIndex.instance.replace(paths: const {}, covers: {'s1': localCover.path});
      expect(svc.getCoverArtUrl('s1'), Uri.file(localCover.path).toString());

      // Downloaded too: the download's own copy wins.
      net.answers['/rest/getCoverArt.view'] = [_jpeg];
      await offline.downloadSong(_song('s1'), _Svc());
      expect(svc.getCoverArtUrl('s1'), Uri.file(offline.getLocalCoverArtPath('s1')!).toString());

      // Big sizes (share cards) still come from the server.
      expect(svc.getCoverArtUrl('s1', size: 900), contains('getCoverArt'));
    });
  });

  group('SubsonicService.scrobble', () {
    SubsonicService svc(http.Client c) => SubsonicService(
          serverUrl: 'https://navi.test', username: 'u', password: 'p', cache: _NoCache(), client: c);

    test('sends the time it was given, or now by default', () async {
      final urls = <Uri>[];
      final client = MockClient((r) async {
        urls.add(r.url);
        return http.Response('{}', 200);
      });
      await svc(client).scrobble('s1', submission: true, timeMs: 1700000000000);
      expect(urls.last.queryParameters['time'], '1700000000000');
      expect(urls.last.queryParameters['submission'], 'true');

      final before = DateTime.now().millisecondsSinceEpoch;
      await svc(client).scrobble('s1', submission: false);
      expect(int.parse(urls.last.queryParameters['time']!), greaterThanOrEqualTo(before));
    });

    test('strict mode reports a failure; the default swallows it', () async {
      final client = MockClient((r) async => http.Response('nope', 503));
      await svc(client).scrobble('s1', submission: true); // fire-and-forget: no throw
      expect(() => svc(client).scrobble('s1', submission: true, strict: true), throwsA(anything));
      final dead = MockClient((r) async => throw const SocketException('down'));
      expect(() => svc(dead).scrobble('s1', submission: true, strict: true), throwsA(anything));
    });
  });

  group('Downloaded list', () {
    test('keeps songs the library mirror does not know, and every downloaded id', () {
      final mirror = [_song('a')];
      final disk = [_song('a'), _song('b')];
      final out = mergeDownloadedSongs(ids: {'a', 'b', 'c'}, mirror: mirror, disk: disk);
      expect(out.map((s) => s.id).toSet(), {'a', 'b', 'c'});
      expect(out.firstWhere((s) => s.id == 'b').title, 'Tb'); // from the file beside the audio
      expect(out.firstWhere((s) => s.id == 'c').title, 'Downloaded song'); // neither knows it
    });

    test('ignores metadata for songs that are no longer downloaded; filters and sorts', () {
      final disk = [_song('a'), _song('gone'), _song('z')];
      final out = mergeDownloadedSongs(ids: {'a', 'z'}, mirror: const [], disk: disk, query: 't');
      expect(out.map((s) => s.id).toSet(), {'a', 'z'});
      final sorted = sortSongs(out, const LibrarySortPreference(direction: LibrarySortDirection.desc));
      expect(sorted.map((s) => s.id), ['z', 'a']);
    });

    test('getDownloadedSongsMetadata reads what downloads saved', () async {
      net.answers['/rest/getCoverArt.view'] = [_jpeg];
      await offline.downloadSong(_song('s1'), _Svc());
      final songs = await offline.getDownloadedSongsMetadata();
      expect(songs.map((s) => s.id), ['s1']);
    });
  });
}

class _NoCache extends Fake implements PlaylistCacheService {}
