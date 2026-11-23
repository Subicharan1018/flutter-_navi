import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/spotify_import/logic/spotify_parser.dart';

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A made-up extended-history row with every field Spotify writes, including the private ones.
Map<String, Object?> _row({
  String ts = '2024-03-05T10:00:00Z',
  Object? ms = 200000,
  String? title = 'Neela Megam',
  String? artist = 'Aarav Kumar',
  String? album = 'Neela',
  String end = 'trackdone',
  Object? skipped = false,
  bool incognito = false,
  String? episode,
  String? audiobook,
}) => {
  'ts': ts,
  'platform': 'Android OS 14 (OnePlus)',
  'ms_played': ms,
  'conn_country': 'IN',
  'ip_addr': '203.0.113.7',
  'master_metadata_track_name': title,
  'master_metadata_album_artist_name': artist,
  'master_metadata_album_album_name': album,
  'spotify_track_uri': 'spotify:track:abc',
  'episode_name': episode,
  'episode_show_name': episode == null ? null : 'Some Show',
  'spotify_episode_uri': episode == null ? null : 'spotify:episode:x',
  'audiobook_title': audiobook,
  'audiobook_uri': audiobook == null ? null : 'spotify:show:y',
  'audiobook_chapter_uri': null,
  'audiobook_chapter_title': null,
  'reason_start': 'clickrow',
  'reason_end': end,
  'shuffle': true,
  'skipped': skipped,
  'offline': false,
  'offline_timestamp': 1700000000000,
  'incognito_mode': incognito,
};

void main() {
  group('extended history', () {
    test('keeps only the needed fields of a music play', () {
      final r = parseSpotifyBytes([('Streaming_History_Audio_2024.json', _bytes([_row()]))]);
      expect(r.plays, hasLength(1));
      final json = r.plays.single.toJson();
      expect(json, {
        't': DateTime.utc(2024, 3, 5, 10).millisecondsSinceEpoch ~/ 1000,
        'ms': 200000,
        'title': 'Neela Megam',
        'artist': 'Aarav Kumar',
        'album': 'Neela',
        'end': 'trackdone',
        'sk': false,
      });
      final wire = jsonEncode(json);
      for (final secret in ['203.0.113.7', 'IN', 'Android', 'OnePlus', 'spotify:track', '1700000000000']) {
        expect(wire.contains(secret), isFalse, reason: secret);
      }
    });

    test('drops episodes, audiobooks, private plays and rows with nothing to match on, and counts each', () {
      final r = parseSpotifyBytes([
        (
          'Streaming_History_Audio_2024.json',
          _bytes([
            _row(),
            _row(title: null, artist: null, episode: 'An Episode'),
            _row(title: null, artist: null, audiobook: 'A Book'),
            _row(incognito: true),
            _row(title: null),
            _row(artist: '  '),
            _row(ts: 'not a time'),
            _row(ms: -5),
            _row(ms: 'x'),
            'not a row',
            _row(ts: '2024-03-05T11:00:00Z', skipped: true, end: 'fwdbtn', ms: 4000),
          ]),
        ),
      ]);
      final s = r.summary;
      expect(r.plays, hasLength(2));
      expect((s.rows, s.kept), (11, 2));
      expect((s.droppedEpisodes, s.droppedAudiobooks, s.droppedPrivate, s.droppedUnusable), (1, 1, 1, 6));
      expect(s.dropped, 9);
      expect(r.plays.last.skipped, isTrue);
      expect(r.plays.last.end, 'fwdbtn');
    });

    test('a missing skipped flag stays absent, and a float length is whole milliseconds', () {
      final r = parseSpotifyBytes([('Streaming_History_Audio_2024.json', _bytes([_row(skipped: null, ms: 1999.7)]))]);
      expect(r.plays.single.skipped, isNull);
      expect(r.plays.single.ms, 1999);
      expect(r.plays.single.toJson().containsKey('sk'), isFalse);
    });

    test('files are merged oldest first, with the date range', () {
      final r = parseSpotifyBytes([
        ('Streaming_History_Audio_2025.json', _bytes([_row(ts: '2025-01-01T00:00:00Z', title: 'B')])),
        ('Streaming_History_Audio_2023.json', _bytes([_row(ts: '2023-06-01T00:00:00Z', title: 'A')])),
      ]);
      expect(r.plays.map((p) => p.title), ['A', 'B']);
      expect(r.summary.firstTs, DateTime.utc(2023, 6).millisecondsSinceEpoch ~/ 1000);
      expect(r.summary.lastTs, DateTime.utc(2025).millisecondsSinceEpoch ~/ 1000);
      expect(r.summary.filesRead, 2);
    });

    test('video, README and other files are ignored unread; a broken history file is counted', () {
      final r = parseSpotifyBytes([
        ('Spotify Extended Streaming History/Streaming_History_Audio_2024.json', _bytes([_row()])),
        ('Spotify Extended Streaming History/Streaming_History_Video_2024.json', _bytes([_row()])),
        ('ReadMeFirst_ExtendedStreamingHistory.pdf', Uint8List.fromList([1, 2, 3])),
        ('Streaming_History_Audio_2025.json', Uint8List.fromList(utf8.encode('{ not json'))),
        ('Streaming_History_Audio_2026.json', _bytes({'not': 'a list'})),
      ]);
      expect(r.plays, hasLength(1));
      expect((r.summary.filesRead, r.summary.filesIgnored, r.summary.filesUnreadable), (1, 2, 2));
    });

    test('a byte-order mark and Windows path separators are fine', () {
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(jsonEncode([_row()]))]);
      final r = parseSpotifyBytes([(r'C:\Users\x\Downloads\Streaming_History_Audio_2024.json', bom)]);
      expect(r.plays, hasLength(1));
    });

    test('Tamil and other non-Latin text survives', () {
      final r = parseSpotifyBytes([
        ('Streaming_History_Audio_2024.json', _bytes([_row(title: 'நீலா மேகம்', artist: 'அருண்')])),
      ]);
      expect((r.plays.single.title, r.plays.single.artist), ('நீலா மேகம்', 'அருண்'));
    });
  });

  group('basic history', () {
    Map<String, Object?> basic({String when = '2023-11-02 11:28', Object? ms = 61000}) =>
        {'endTime': when, 'artistName': 'Aarav Kumar', 'trackName': 'Neela Megam', 'msPlayed': ms};

    test('reads StreamingHistory0.json with times taken as UTC and no reason', () {
      final r = parseSpotifyBytes([
        ('StreamingHistory0.json', _bytes([basic(), basic(ms: 'x'), basic(when: 'nope')])),
        ('StreamingHistory_music_1.json', _bytes([basic(when: '2023-11-03 08:00')])),
        ('StreamingHistory_podcast_0.json', _bytes([basic()])),
      ]);
      expect(r.summary.format, SpotifyFormat.basic);
      expect(r.plays, hasLength(2));
      expect(r.plays.first.t, DateTime.utc(2023, 11, 2, 11, 28).millisecondsSinceEpoch ~/ 1000);
      expect(r.plays.first.end, '');
      expect(r.summary.droppedUnusable, 2);
      expect(r.summary.filesIgnored, 1);
      expect(r.plays.first.toJson().keys.toSet(), {'t', 'ms', 'title', 'artist'});
    });

    test('the extended files win when both kinds are present', () {
      final r = parseSpotifyBytes([
        ('Streaming_History_Audio_2024.json', _bytes([_row()])),
        ('StreamingHistory0.json', _bytes([basic()])),
      ]);
      expect(r.summary.format, SpotifyFormat.extended);
      expect(r.plays, hasLength(1));
      expect(r.summary.filesIgnored, 1);
    });
  });

  test('nothing that looks like a Spotify history is a clear error', () {
    expect(
      () => parseSpotifyBytes([('photos.json', _bytes([1])), ('notes.txt', Uint8List(0))]),
      throwsA(isA<SpotifyParseException>().having((e) => e.message, 'message', contains('No Spotify listening history'))),
    );
  });

  test('pages are at most 1,000 plays, in order, and cover every play once', () {
    final plays = [for (var i = 0; i < 2501; i++) SpotifyPlay(t: 1700000000 + i, ms: 1, title: 't$i', artist: 'a')];
    final pages = spotifyPages(plays);
    expect(pages.map((p) => p.length), [1000, 1000, 501]);
    expect(pages.expand((p) => p).map((p) => p.title), plays.map((p) => p.title));
    expect(spotifyPages(const []), isEmpty);
  });

  group('files on disk, read in an isolate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('spotify_parser_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a ZIP with history, video and a README: only the music history is read', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('Spotify Extended Streaming History/Streaming_History_Audio_2024.json', _bytes([_row(), _row(incognito: true)])))
        ..addFile(ArchiveFile.bytes('Spotify Extended Streaming History/Streaming_History_Video_2024.json', _bytes([_row()])))
        ..addFile(ArchiveFile.bytes('Spotify Extended Streaming History/ReadMeFirst_ExtendedStreamingHistory.pdf', Uint8List(40)));
      final zip = File('${dir.path}/my_spotify_data.zip')..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final r = await parseSpotifyFiles([zip.path]);
      expect(r.plays, hasLength(1));
      expect((r.summary.droppedPrivate, r.summary.filesIgnored, r.summary.filesRead), (1, 2, 1));
    });

    test('loose JSON files can be chosen instead of the ZIP', () async {
      final a = File('${dir.path}/Streaming_History_Audio_2024.json')..writeAsBytesSync(_bytes([_row()]));
      final b = File('${dir.path}/Streaming_History_Audio_2025.json')..writeAsBytesSync(_bytes([_row(ts: '2025-02-02T00:00:00Z')]));
      final r = await parseSpotifyFiles([a.path, b.path]);
      expect(r.plays, hasLength(2));
    });

    test('a file that is not a ZIP gives the readable error', () async {
      final bad = File('${dir.path}/broken.zip')..writeAsBytesSync([1, 2, 3, 4, 5]);
      await expectLater(parseSpotifyFiles([bad.path]), throwsA(isA<SpotifyParseException>()));
    });

    test('a real export, if SPOTIFY_SAMPLE points at one: counts only, never contents', () async {
      final path = Platform.environment['SPOTIFY_SAMPLE'];
      if (path == null) return;
      final files = [for (final f in Directory(path).listSync().whereType<File>()) if (f.path.endsWith('.json')) f.path];
      final r = await parseSpotifyFiles(files);
      final s = r.summary;
      // ignore: avoid_print
      print('SPOTIFY_SAMPLE rows=${s.rows} kept=${s.kept} episodes=${s.droppedEpisodes} private=${s.droppedPrivate} '
          'unusable=${s.droppedUnusable} files=${s.filesRead}/${s.filesIgnored}/${s.filesUnreadable} '
          'first=${s.firstTs} last=${s.lastTs}');
      expect(s.kept + s.dropped, s.rows);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
