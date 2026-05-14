import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/listening_event_collector.dart';
import 'package:sqlite3/open.dart';

import '../helpers/test_utils.dart';
// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('/usr/lib64/libsqlite3.so.0');
      } catch (e) {
        return DynamicLibrary.open('libsqlite3.so');
      }
    });
  });

  late AppDatabase db;
  late ListeningEventCollector collector;
  late DateTime fakeNow;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fakeNow = DateTime(2024, 1, 1, 12, 0, 0);
    collector = ListeningEventCollector(db, clock: () => fakeNow);
  });

  tearDown(() async {
    await collector.dispose();
    await pumpMicrotasks();
    await db.close();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Fingerprint deduplication
  // ──────────────────────────────────────────────────────────────────────────

  group('Fingerprint deduplication', () {
    test(
      'same song+position within 500ms → second call collapsed, 1 event',
      () async {
        final songA = makeSong(id: 'A');
        final songB = makeSong(id: 'B');

        // First call: opens event for A.
        collector.onSongStarted(
          song: songA,
          queuePosition: 0,
          sourceContext: 'test',
          transitionType: 'manual',
        );

        // Advance clock by only 400ms — within the 500ms dedup window.
        fakeNow = fakeNow.add(const Duration(milliseconds: 400));

        // Second call with same fingerprint → should be collapsed.
        collector.onSongStarted(
          song: songA,
          queuePosition: 0,
          sourceContext: 'test',
          transitionType: 'manual',
        );

        // Close the open event by starting B (with enough play time for persist).
        fakeNow = fakeNow.add(const Duration(seconds: 3));
        collector.onSongStarted(
          song: songB,
          queuePosition: 1,
          sourceContext: 'test',
          transitionType: 'skip',
          prevSong: songA,
          positionAtSwitch: const Duration(seconds: 3),
        );

        await pumpMicrotasks();

        final events = await db.select(db.playEvents).get();
        final songAEvents = events.where((e) => e.songId == 'A').toList();
        // The second call was collapsed — only 1 event for song A.
        expect(songAEvents.length, equals(1));
      },
    );

    test('same song+position after 500ms → two distinct events', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');
      final songC = makeSong(id: 'C');

      // Play A the first time.
      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      // Switch to B after 3s to close A's first event.
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'skip',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 3),
      );

      // Advance 600ms past the dedup window.
      fakeNow = fakeNow.add(const Duration(milliseconds: 600));

      // Play A again at the same queue position — fingerprint is same but
      // time gap > 500ms, so a new event should be created.
      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
        prevSong: songB,
        positionAtSwitch: const Duration(milliseconds: 600),
      );

      // Close A's second event by switching to C.
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songC,
        queuePosition: 2,
        sourceContext: 'test',
        transitionType: 'skip',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      final events = await db.select(db.playEvents).get();
      final songAEvents = events.where((e) => e.songId == 'A').toList();
      expect(songAEvents.length, equals(2));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Duration thresholds
  // ──────────────────────────────────────────────────────────────────────────

  group('Duration thresholds', () {
    test('play < 2.0s → PlayEvent NOT persisted', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');

      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      // Switch after only 1.9s — below 2s threshold.
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'skip',
        prevSong: songA,
        positionAtSwitch: const Duration(milliseconds: 1900),
      );

      await pumpMicrotasks();

      final events = await db.select(db.playEvents).get();
      final songAEvents = events.where((e) => e.songId == 'A').toList();
      expect(
        songAEvents.length,
        equals(0),
        reason: 'Short plays below 2s must not be persisted',
      );
    });

    test('play ≥ 2.0s → PlayEvent persisted with correct duration', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');

      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      // Switch after 3s — above threshold.
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'skip',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      final events = await db.select(db.playEvents).get();
      final songAEvents = events.where((e) => e.songId == 'A').toList();
      expect(songAEvents.length, equals(1));
      expect(songAEvents.first.playDurSec, greaterThanOrEqualTo(2));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Co-play SongPair thresholds
  // ──────────────────────────────────────────────────────────────────────────

  group('Co-play SongPair thresholds', () {
    test('transition < 5.0s → no SongPair row created', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');

      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'sequential',
      );

      // Play A for only 4.9s — below _kMinPairDurationSec (5.0s).
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songA,
        positionAtSwitch: const Duration(milliseconds: 4900),
      );

      await pumpMicrotasks();

      final pairs = await db.select(db.songPairs).get();
      expect(
        pairs.isEmpty,
        isTrue,
        reason: 'Pairs must not be recorded for plays under 5s',
      );
    });

    test('transition ≥ 5.0s → SongPair row created', () async {
      final songA = makeSong(id: 'A', duration: 10);
      final songB = makeSong(id: 'B');

      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'sequential',
      );

      // Play A for 6s — above threshold.
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 6),
      );

      await pumpMicrotasks();

      final pairs = await db.select(db.songPairs).get();
      expect(pairs.length, equals(1));
      expect(pairs.first.prevSongId, equals('A'));
      expect(pairs.first.currentSongId, equals('B'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Session timeout
  // ──────────────────────────────────────────────────────────────────────────

  group('Session timeout', () {
    test('31 min gap → new sessionId generated', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');
      final songC = makeSong(id: 'C');
      final songD = makeSong(id: 'D');

      // Start session 1 with song A.
      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      // Close A with song B.
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      // Advance 31 minutes — past the 30 min session timeout.
      fakeNow = fakeNow.add(const Duration(minutes: 31));

      // Start song C — should trigger new session.
      collector.onSongStarted(
        song: songC,
        queuePosition: 2,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      // Close C with song D.
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songD,
        queuePosition: 3,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songC,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      final events = await db.select(db.playEvents).get();
      expect(events.length, greaterThanOrEqualTo(2));

      final sessionA = events.firstWhere((e) => e.songId == 'A').sessionId;
      final sessionC = events.firstWhere((e) => e.songId == 'C').sessionId;

      expect(
        sessionA,
        isNot(equals(sessionC)),
        reason: '31-minute gap must trigger a new session UUID',
      );
    });

    test('29 min gap → same sessionId maintained', () async {
      final songA = makeSong(id: 'A');
      final songB = makeSong(id: 'B');
      final songC = makeSong(id: 'C');
      final songD = makeSong(id: 'D');

      collector.onSongStarted(
        song: songA,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songB,
        queuePosition: 1,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songA,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      // Only 29 minutes — within session window.
      fakeNow = fakeNow.add(const Duration(minutes: 29));

      collector.onSongStarted(
        song: songC,
        queuePosition: 2,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      fakeNow = fakeNow.add(const Duration(seconds: 3));
      collector.onSongStarted(
        song: songD,
        queuePosition: 3,
        sourceContext: 'test',
        transitionType: 'sequential',
        prevSong: songC,
        positionAtSwitch: const Duration(seconds: 3),
      );

      await pumpMicrotasks();

      final events = await db.select(db.playEvents).get();
      final sessionA = events.firstWhere((e) => e.songId == 'A').sessionId;
      final sessionC = events.firstWhere((e) => e.songId == 'C').sessionId;

      expect(
        sessionA,
        equals(sessionC),
        reason: '29-minute gap should not trigger a new session',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SongMetadata upsert
  // ──────────────────────────────────────────────────────────────────────────

  group('SongMetadata upsert', () {
    test('onSongStarted upserts metadata row for the started song', () async {
      final song = makeSong(id: '1', title: 'MyTitle', artist: 'MyArtist');

      collector.onSongStarted(
        song: song,
        queuePosition: 0,
        sourceContext: 'test',
        transitionType: 'manual',
      );

      await pumpMicrotasks();

      final metadata = await db.select(db.songMetadata).get();
      expect(metadata.any((m) => m.songId == '1'), isTrue);
      final row = metadata.firstWhere((m) => m.songId == '1');
      expect(row.trackName, equals('MyTitle'));
      expect(row.artistName, equals('MyArtist'));
    });
  });
}
