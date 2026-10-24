import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/features/local_library/logic/download_location.dart';
import 'package:navivibe/features/local_library/logic/file_source.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/features/local_library/logic/local_library_service.dart';
import 'package:navivibe/features/local_library/logic/local_models.dart';
import 'package:navivibe/features/local_library/logic/matcher.dart';
import 'package:navivibe/features/local_library/logic/scanner.dart';
import 'package:navivibe/features/local_library/logic/tag_reader.dart';

/// A tiny ID3v2.3 MP3: tag frames, then a few MPEG-1 Layer III frames.
Uint8List fixtureMp3({String title = 'Ala Bolelo', String artist = 'Anirudh', String album = 'Jailer 2', int track = 3}) {
  List<int> frame(String id, String text) {
    final body = [0, ...latin1.encode(text)];
    return [
      ...ascii.encode(id),
      (body.length >> 24) & 0xff,
      (body.length >> 16) & 0xff,
      (body.length >> 8) & 0xff,
      body.length & 0xff,
      0,
      0,
      ...body,
    ];
  }

  final frames = [
    ...frame('TIT2', title),
    ...frame('TPE1', artist),
    ...frame('TALB', album),
    ...frame('TRCK', '$track'),
    ...frame('TYER', '2025'),
  ];
  final size = frames.length;
  final syncsafe = [(size >> 21) & 0x7f, (size >> 14) & 0x7f, (size >> 7) & 0x7f, size & 0x7f];
  // 128 kbps, 44.1 kHz, no padding: frame length 417 bytes.
  final audio = <int>[];
  for (var i = 0; i < 8; i++) {
    audio.addAll([0xFF, 0xFB, 0x90, 0x00, ...List.filled(413, 0)]);
  }
  return Uint8List.fromList([...ascii.encode('ID3'), 3, 0, 0, ...syncsafe, ...frames, ...audio]);
}

Future<List<ScanEvent>> collect(Stream<ScanEvent> s) => s.toList();

void main() {
  late Directory root;
  late Directory art;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('navi_local_');
    art = Directory('${root.path}${Platform.pathSeparator}art');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<File> put(String rel, List<int> bytes) async {
    final f = File('${root.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return f;
  }

  LocalFolder folder() => LocalFolder(id: 'f1', uri: root.path, name: 'Music');

  group('names and ids', () {
    test('classifies audio, lyrics and folder art', () {
      expect(isScannable('a.MP3'), isTrue);
      expect(isScannable('a.lrc'), isTrue);
      expect(isScannable('cover.jpg'), isTrue);
      expect(isScannable('holiday.jpg'), isFalse);
      expect(isScannable('notes.txt'), isFalse);
    });

    test('local ids are stable per path and never look like server ids', () {
      final a = localSongIdFor(r'C:\Music\a.mp3');
      expect(a, localSongIdFor(r'C:\Music\a.mp3'));
      expect(a, isNot(localSongIdFor(r'C:\Music\b.mp3')));
      expect(isLocalSongId(a), isTrue);
      expect(isLocalSongId('8f3a2c'), isFalse);
    });

    test('Android tree URIs read as paths', () {
      expect(
        displayFolderPath('content://com.android.externalstorage.documents/tree/primary%3AMusic%2FRock'),
        'Internal storage/Music/Rock',
      );
      expect(displayFolderPath(r'D:\Music'), r'D:\Music');
    });

    test('parses ReplayGain values', () {
      expect(parseGain('-6.54 dB'), -6.54);
      expect(parseGain('+2,1 dB'), 2.1);
      expect(parseGain('0.988'), 0.988);
      expect(parseGain(null), isNull);
      expect(parseGain('n/a'), isNull);
    });
  });

  group('scanner', () {
    test('reads tags, the sidecar lyrics and a folder cover; ignores other files', () async {
      await put('Album/01.mp3', fixtureMp3());
      await put('Album/01.lrc', utf8.encode('[00:01.00]Hello\n[00:05.00]World'));
      await put('Album/cover.jpg', [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      await put('Album/readme.txt', [1]);

      final events = await collect(scanFolders(
        sourceFor: (_) => const IoFileSource(),
        folders: [folder()],
        known: const {},
        artDir: art,
      ));

      final batch = events.whereType<ScanBatch>().single;
      final t = batch.tracks.single;
      expect(t.title, 'Ala Bolelo');
      expect(t.artist, 'Anirudh');
      expect(t.album, 'Jailer 2');
      expect(t.track, 3);
      expect(t.year, 2025);
      expect(t.suffix, 'mp3');
      expect(t.lyrics, contains('[00:01.00]Hello'));
      expect(t.coverPath, isNotNull);
      expect(File(t.coverPath!).existsSync(), isTrue);
      expect(events.whereType<ScanFolderDone>().single.seen, {t.path});
      expect(events.whereType<ScanListed>().single.total, 1);
    });

    test('a file with unreadable tags is kept under its file name', () async {
      await put('Rips/Some Track.mp3', [1, 2, 3, 4, 5, 6, 7, 8]);
      final events = await collect(scanFolders(
        sourceFor: (_) => const IoFileSource(),
        folders: [folder()],
        known: const {},
        artDir: art,
      ));
      final t = events.whereType<ScanBatch>().single.tracks.single;
      expect(t.title, 'Some Track');
      expect(t.artist, 'Unknown Artist');
    });

    test('unchanged files are skipped on the next scan, changed ones re-read', () async {
      final f = await put('a.mp3', fixtureMp3());
      List<ScanEvent> run(Map<String, String> known) => [];
      Future<List<ScanEvent>> scan(Map<String, String> known) =>
          collect(scanFolders(sourceFor: (_) => const IoFileSource(), folders: [folder()], known: known, artDir: art));

      final first = await scan({});
      final track = first.whereType<ScanBatch>().single.tracks.single;
      final known = {track.path: track.fingerprint};

      final second = await scan(known);
      expect(second.whereType<ScanBatch>(), isEmpty);
      expect(second.whereType<ScanFolderDone>().single.seen, {track.path});

      await f.writeAsBytes(fixtureMp3(title: 'Renamed'));
      await f.setLastModified(DateTime.now().add(const Duration(minutes: 5)));
      final third = await scan(known);
      expect(third.whereType<ScanBatch>().single.tracks.single.title, 'Renamed');
      run(known);
    });

    test('a missing folder fails alone and does not report its files as gone', () async {
      await put('a.mp3', fixtureMp3());
      final gone = LocalFolder(id: 'f2', uri: '${root.path}${Platform.pathSeparator}nope', name: 'Gone');
      final events = await collect(scanFolders(
        sourceFor: (_) => const IoFileSource(),
        folders: [gone, folder()],
        known: const {},
        artDir: art,
      ));
      expect(events.whereType<ScanFolderFailed>().single.folderId, 'f2');
      expect(events.whereType<ScanFolderDone>().single.folderId, 'f1');
    });

    test('runs in a background isolate', () async {
      await put('a.mp3', fixtureMp3());
      final events = await scanInIsolate(folders: [folder()], known: const {}, artDir: art.path).toList();
      expect(events.whereType<ScanBatch>().single.tracks.single.title, 'Ala Bolelo');
    });
  });

  group('library service', () {
    late AppDatabase db;
    late MemoryFolderStore store;
    late LocalLibraryService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      store = MemoryFolderStore();
      service = LocalLibraryService(
        db,
        store,
        releaseFolder: (_) async {},
        runScan: ({required folders, required known}) =>
            scanFolders(sourceFor: (_) => const IoFileSource(), folders: folders, known: known, artDir: art),
      );
    });
    tearDown(() async {
      LocalLibraryIndex.instance.clear();
      await db.close();
    });

    test('adds, rescans incrementally, and drops removed files', () async {
      await service.addFolder(folder());
      await put('a.mp3', fixtureMp3(title: 'One'));
      final b = await put('b.mp3', fixtureMp3(title: 'Two', track: 4));

      var summary = await service.scan();
      expect(summary.added, 2);
      expect((await service.allRows()).map((r) => r.title), unorderedEquals(['One', 'Two']));

      summary = await service.scan();
      expect(summary.added, 0);

      await b.delete();
      await put('c.mp3', fixtureMp3(title: 'Three'));
      summary = await service.scan();
      expect(summary.added, 1);
      expect(summary.removed, 1);
      expect((await service.allRows()).map((r) => r.title), unorderedEquals(['One', 'Three']));
    });

    test('a folder that cannot be listed keeps its songs', () async {
      await service.addFolder(folder());
      await put('a.mp3', fixtureMp3());
      await service.scan();
      await root.delete(recursive: true);
      final summary = await service.scan();
      expect(summary.failedFolders.keys, ['f1']);
      expect(await service.allRows(), hasLength(1));
      await root.create();
    });

    test('matched copies are hidden from lists and play from the device under the server id', () async {
      await service.addFolder(folder());
      await put('a.mp3', fixtureMp3(title: 'Ala Bolelo', artist: 'Anirudh'));
      await put('b.mp3', fixtureMp3(title: 'Only Here', artist: 'Someone'));
      await db.into(db.songMetadata).insert(SongMetadataCompanion.insert(
            songId: 'srv-1',
            trackName: 'Ala Bolelo',
            artistName: 'Anirudh',
            albumName: 'Jailer 2',
            durationSec: 0,
            updatedAt: 0,
          ));

      await service.scan();

      final listed = await service.watchSongs().first;
      expect(listed.map((s) => s.title), ['Only Here']);
      expect(await service.search('ala'), isEmpty);
      expect((await service.search('only')).single.title, 'Only Here');
      expect(await service.watchCounts().first, (2, 1));

      final localPath = LocalLibraryIndex.instance.pathFor('srv-1');
      expect(localPath, endsWith('a.mp3'));
      expect(LocalLibraryIndex.instance.pathFor(listed.single.id), endsWith('b.mp3'));
      expect(LocalLibraryIndex.instance.pathFor('other'), isNull);
    });

    test('removing a folder removes its songs and its index entries', () async {
      await service.addFolder(folder());
      await put('a.mp3', fixtureMp3());
      await service.scan();
      expect(LocalLibraryIndex.instance.length, 1);
      await service.removeFolder('f1');
      expect(await service.allRows(), isEmpty);
      expect(LocalLibraryIndex.instance.length, 0);
      expect(service.folders, isEmpty);
    });

    test('lyrics come back for the local id and for the matched server id', () async {
      await service.addFolder(folder());
      await put('a.mp3', fixtureMp3(title: 'Sung'));
      await put('a.lrc', utf8.encode('[00:01.00]la la'));
      await db.into(db.songMetadata).insert(SongMetadataCompanion.insert(
            songId: 'srv-9',
            trackName: 'Sung',
            artistName: 'Anirudh',
            albumName: 'x',
            durationSec: 0,
            updatedAt: 0,
          ));
      await service.scan();
      final row = (await service.allRows()).single;
      expect(await service.lyricsFor(row.songId), contains('la la'));
      expect(await service.lyricsFor('srv-9'), contains('la la'));
      expect(await service.lyricsFor('nobody'), isNull);
    });
  });

  group('matcher', () {
    MatchKey k(String id, String title, String artist, int d) => MatchKey(id, title, artist, d);

    test('matches on title and artist within the duration tolerance', () {
      final m = matchLocalToServer(
        [k('l1', 'Ala Bolelo', 'Anirudh Ravichander', 215)],
        [k('s1', 'Ala Bolelo', 'Anirudh Ravichander', 217)],
      );
      expect(m, {'l1': 's1'});
    });

    test('ignores case, accents, punctuation and feat. credits', () {
      expect(normalizeForMatch('Café del Mar (Radio Edit)'), normalizeForMatch('CAFE DEL MAR'));
      expect(normalizeForMatch('Song feat. Someone'), normalizeForMatch('Song'));
      expect(
        matchLocalToServer([k('l', 'Hey, Jude!', 'The Beatles', 431)], [k('s', 'hey jude', 'the beatles', 430)]),
        {'l': 's'},
      );
    });

    test('a different length is a different recording', () {
      expect(matchLocalToServer([k('l', 'Song', 'A', 200)], [k('s', 'Song', 'A', 260)]), isEmpty);
    });

    test('an unknown duration on either side still matches by name', () {
      expect(matchLocalToServer([k('l', 'Song', 'A', 0)], [k('s', 'Song', 'A', 200)]), {'l': 's'});
    });

    test('different artists do not match; a collaboration credit does', () {
      expect(matchLocalToServer([k('l', 'Song', 'Alice', 200)], [k('s', 'Song', 'Bob', 200)]), isEmpty);
      expect(matchLocalToServer([k('l', 'Song', 'Alice', 200)], [k('s', 'Song', 'Alice & Bob', 200)]), {'l': 's'});
    });

    test('closest duration wins and a server song is used once', () {
      final m = matchLocalToServer(
        [k('l1', 'Song', 'A', 200), k('l2', 'Song', 'A', 200)],
        [k('s1', 'Song', 'A', 203), k('s2', 'Song', 'A', 200)],
      );
      expect(m['l1'], 's2');
      expect(m['l2'], 's1');
    });
  });

  group('download location', () {
    test('default is the app folder; a chosen folder gets its own subfolder', () {
      final sep = Platform.pathSeparator;
      expect(resolveOfflineDir(appDocs: 'docs'), 'docs${sep}offline_music');
      expect(resolveOfflineDir(appDocs: 'docs', custom: ''), 'docs${sep}offline_music');
      expect(resolveOfflineDir(appDocs: 'docs', custom: '${sep}music'), '${sep}music$sep$downloadsFolderName');
      expect(resolveOfflineDir(appDocs: 'docs', custom: '${sep}music$sep'), '${sep}music$sep$downloadsFolderName');
    });

    test('a writable folder passes, an impossible one explains itself', () async {
      expect(await checkWritable('${root.path}${Platform.pathSeparator}new'), isNull);
      final file = await put('plain.txt', [1]);
      final error = await checkWritable('${file.path}${Platform.pathSeparator}inside');
      expect(error, contains('can’t write'));
    });

    test('moves every file, keeps what is already there, reports progress', () async {
      await put('from/a.mp3', [1, 2, 3]);
      await put('from/a.song.json', [4]);
      await put('from/b.mp3', [5]);
      await put('to/b.mp3', [9, 9]);
      final progress = <(int, int)>[];
      final r = await moveDirectoryFiles(
        '${root.path}${Platform.pathSeparator}from',
        '${root.path}${Platform.pathSeparator}to',
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect((r.moved, r.failed), (3, 0));
      expect(progress.last, (3, 3));
      expect(Directory('${root.path}${Platform.pathSeparator}from').listSync(), isEmpty);
      final to = Directory('${root.path}${Platform.pathSeparator}to').listSync().map((e) => e.uri.pathSegments.last);
      expect(to, unorderedEquals(['a.mp3', 'a.song.json', 'b.mp3']));
      expect(await File('${root.path}${Platform.pathSeparator}to${Platform.pathSeparator}b.mp3').length(), 2);
    });

    test('directory size adds the files', () async {
      await put('d/a', [1, 2, 3]);
      await put('d/b', [1]);
      expect(await directorySize('${root.path}${Platform.pathSeparator}d'), 4);
      expect(await directorySize('${root.path}${Platform.pathSeparator}missing'), 0);
    });

    test('free space is read from df and from PowerShell output', () async {
      const df = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 1000 400 600 40% /';
      expect(parseDfAvailableBytes(df), 600 * 1024);
      expect(parseDfAvailableBytes('garbage'), isNull);
      final free = await freeSpaceBytes(
        Platform.isWindows ? r'C:\x' : '/',
        android: false,
        run: (exe, args) async => ProcessResult(0, 0, Platform.isWindows ? '1048576\r\n' : df, ''),
      );
      expect(free, Platform.isWindows ? 1048576 : 600 * 1024);
      final failing = await freeSpaceBytes('/', android: false, run: (_, _) async => throw const OSError('nope'));
      expect(failing, isNull);
    });
  });
}
