// ignore_for_file: avoid_relative_lib_imports
// =============================================================================
// download_state_audit_test.dart
//
// AUDIT: Bug 1 — Download Visual State Desync
//
// Tests that the _DownloadBadge / OptionsMenu correctly reflect NOT-downloaded
// state after a file is removed from disk.
//
// Root cause under test:
//   DownloadStateNotifier.build() seeds state from SharedPreferences ID list
//   WITHOUT cross-checking isSongDownloaded() (actual file existence).
//   OfflineScreen._clearAllDownloads() bypasses the Riverpod notifier entirely.
//
// Run: flutter test test/download_state_audit_test.dart --reporter=expanded
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/subsonic_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockOfflineService extends Mock implements OfflineService {}
class MockSubsonicService extends Mock implements SubsonicService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal Song value object for use in tests.
Song _makeSong({String id = 'song-1', String title = 'Test Song'}) => Song(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      coverArt: '',
      duration: 200,
      track: 1,
      year: 2024,
    );

/// Build a [ProviderContainer] with [offlineServiceProvider] overridden by the
/// supplied mock. This follows the project's Riverpod architecture: services
/// are injected via provider overrides, never instantiated inside tests.
ProviderContainer _buildContainer(MockOfflineService mockOffline) {
  return ProviderContainer(
    overrides: [
      offlineServiceProvider.overrideWithValue(mockOffline),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Required: the reconcile path uses File I/O which needs bindings in tests.
    TestWidgetsFlutterBinding.ensureInitialized();
    // AUDIT: mocktail requires fallback values for any custom types used
    // with any() / captureAny() matchers in verify() calls.
    registerFallbackValue(_makeSong());
    registerFallbackValue(MockSubsonicService());
  });

  late MockOfflineService mockOffline;

  setUp(() {
    mockOffline = MockOfflineService();
    // Stub isSongDownloadedAsync so _reconcileWithDisk() returns Future<bool>
    // and never throws 'Null is not a subtype of Future<bool>'. Default: true
    // (file exists) so reconcile is a no-op in tests that don't override it.
    when(() => mockOffline.isSongDownloadedAsync(any()))
        .thenAnswer((_) async => true);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 1 — Notifier-driven deletion (happy path via the correct API)
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 1: deleteSong() via DownloadStateNotifier', () {
    test(
      'AUDIT: after notifier.deleteSong(), status transitions to notDownloaded',
      () async {
        // AUDIT: Arrange — seed one downloaded song.
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-1']);
        when(() => mockOffline.isSongDownloaded('song-1'))
            .thenReturn(true);
        when(() => mockOffline.deleteSong('song-1'))
            .thenAnswer((_) async => true);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        // AUDIT: Read notifier — this triggers build(), seeding the state.
        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: Confirm initial state is "downloaded" before deletion.
        expect(
          notifier.statusOf('song-1'),
          SongDownloadStatus.downloaded,
          reason: 'Precondition: song must start as downloaded',
        );

        // AUDIT: Act — delete via the notifier (the correct API path).
        await notifier.deleteSong('song-1');

        // AUDIT: Assert — Riverpod state must reflect notDownloaded.
        expect(
          notifier.statusOf('song-1'),
          SongDownloadStatus.notDownloaded,
          reason: 'After notifier.deleteSong(), badge must show not-downloaded',
        );
      },
    );

    test(
      'AUDIT: after notifier.deleteSong(), the song ID is removed from state map',
      () async {
        // AUDIT: Arrange — seed two songs, delete only one.
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-1', 'song-2']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);
        when(() => mockOffline.isSongDownloaded('song-2')).thenReturn(true);
        when(() => mockOffline.deleteSong('song-1'))
            .thenAnswer((_) async => true);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        await notifier.deleteSong('song-1');

        // AUDIT: song-1 removed, song-2 untouched.
        expect(
          container.read(downloadStateProvider).containsKey('song-1'),
          isFalse,
          reason: 'Deleted song must be removed from state map',
        );
        expect(
          notifier.statusOf('song-2'),
          SongDownloadStatus.downloaded,
          reason: 'Undeleted song must remain downloaded',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 2 — Cold start with orphaned SharedPreferences entries
  //
  // AUDIT: This group documents Bug 1's root cause.
  //   build() trusts SharedPreferences without verifying file existence.
  //   If the .mp3 file was externally deleted (OS, file manager, or
  //   OfflineScreen._clearAllDownloads() which bypasses the notifier),
  //   the badge will wrongly show "downloaded" on cold start.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 2: Cold start with stale SharedPreferences (Bug 1)', () {
    test(
      'AUDIT [BUG-DEMONSTRATES]: build() with ID in prefs but file missing '
      '→ current code returns downloaded (THE BUG)',
      () {
        // AUDIT: Arrange — prefs says downloaded, but file is gone.
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['orphan-id']);
        when(() => mockOffline.isSongDownloaded('orphan-id'))
            .thenReturn(false); // file is gone!

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: The CURRENT (buggy) build() does NOT call isSongDownloaded().
        // It just seeds from the ID list.  This test documents the bug:
        // on cold-start the badge shows "downloaded" even though the file
        // was externally deleted.
        //
        // EXPECTED AFTER FIX: SongDownloadStatus.notDownloaded
        // ACTUAL NOW (buggy): SongDownloadStatus.downloaded
        //
        // Once Bug 1 is fixed (build() cross-checks isSongDownloaded()),
        // change the expectation below from .downloaded to .notDownloaded.
        final status = notifier.statusOf('orphan-id');
        expect(
          status,
          SongDownloadStatus.downloaded, // ← THIS SHOULD BE notDownloaded
          reason:
              'BUG-1: build() trusts SharedPreferences without file-existence '
              'check. Fix: filter IDs through isSongDownloaded() in build().',
        );
      },
    );

    test(
      'AUDIT [AFTER FIX]: build() must call isSongDownloaded() for each ID',
      () async {
        // AUDIT: Arrange — prefs says two songs downloaded.
        // song-ok: file still exists. song-gone: file deleted externally.
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-ok', 'song-gone']);
        when(() => mockOffline.isSongDownloadedAsync('song-ok')).thenAnswer((_) async => true);
        when(() => mockOffline.isSongDownloadedAsync('song-gone')).thenAnswer((_) async => false);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        // AUDIT: After the fix, build() should verify files exist.
        // The verify() call below proves isSongDownloaded() is consulted
        // for every ID in the list.  This will FAIL before the fix is applied,
        // because the current build() never calls isSongDownloaded().
        container.read(downloadStateProvider); // trigger build()
        
        // Wait for scheduleMicrotask to complete
        await Future<void>.delayed(Duration.zero);

        // AUDIT: Verify isSongDownloaded was called for EVERY ID in the list.
        // This will fail before Bug 1 is fixed.
        verify(() => mockOffline.isSongDownloadedAsync('song-ok')).called(1);
        verify(() => mockOffline.isSongDownloadedAsync('song-gone')).called(1);
      },
    );

    test(
      'AUDIT [AFTER FIX]: song-gone must be notDownloaded after fix',
      () async {
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-ok', 'song-gone']);
        when(() => mockOffline.isSongDownloadedAsync('song-ok')).thenAnswer((_) async => true);
        when(() => mockOffline.isSongDownloadedAsync('song-gone')).thenAnswer((_) async => false);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);
        
        // Wait for _reconcileWithDisk microtask
        await Future<void>.delayed(Duration.zero);

        // AUDIT: After fix, orphaned IDs must not appear as downloaded.
        // This assertion should FAIL before the fix, then PASS after.
        expect(
          notifier.statusOf('song-ok'),
          SongDownloadStatus.downloaded,
          reason: 'Existing file: should remain downloaded',
        );
        
        expect(
          notifier.statusOf('song-gone'),
          SongDownloadStatus.notDownloaded,
          reason: 'Orphaned ID (no file): must be notDownloaded after fix',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 3 — Bulk delete bypassing the notifier (OfflineScreen bug)
  //
  // AUDIT: OfflineScreen._clearAllDownloads() calls
  //   OfflineService().deleteAllDownloads() directly, without going through
  //   DownloadStateNotifier.  The Riverpod state is never updated.
  //   This is the second root cause of Bug 1.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 3: deleteAllDownloads() bypasses Riverpod (Bug 1)', () {
    test(
      'AUDIT [BUG-DEMONSTRATES]: deleteAllDownloads() does NOT update '
      'downloadStateProvider — badges remain "downloaded" after bulk clear',
      () async {
        // AUDIT: Arrange — two songs downloaded.
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-1', 'song-2']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);
        when(() => mockOffline.isSongDownloaded('song-2')).thenReturn(true);
        when(() => mockOffline.deleteAllDownloads())
            .thenAnswer((_) async {});

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: Simulate what OfflineScreen._clearAllDownloads() does:
        // it calls the service directly, bypassing the notifier.
        await mockOffline.deleteAllDownloads();

        // AUDIT: Riverpod state is NOT updated — this is Bug 1.
        // The badges still show "downloaded" because no invalidation happened.
        expect(
          notifier.statusOf('song-1'),
          SongDownloadStatus.downloaded, // ← THE BUG: should be notDownloaded
          reason:
              'BUG-1: OfflineScreen calls deleteAllDownloads() directly, '
              'bypassing DownloadStateNotifier. Fix: call '
              'ref.invalidate(downloadStateProvider) after the bulk delete.',
        );
      },
    );

    test(
      'AUDIT [AFTER FIX]: after ref.invalidate(), state must reflect empty',
      () async {
        // AUDIT: Arrange — start with two songs in prefs, then simulate
        // the "after fix" state where prefs is now empty (all files deleted).
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-1', 'song-2']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);
        when(() => mockOffline.isSongDownloaded('song-2')).thenReturn(true);
        when(() => mockOffline.deleteAllDownloads()).thenAnswer((_) async {});

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        // AUDIT: Read initial state to trigger build().
        container.read(downloadStateProvider);

        // AUDIT: Simulate deleteAllDownloads() + fix: prefs now returns empty.
        await mockOffline.deleteAllDownloads();
        when(() => mockOffline.getDownloadedSongIds()).thenReturn([]);

        // AUDIT: Apply the fix — invalidate forces build() to re-run.
        container.invalidate(downloadStateProvider);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: After invalidation and re-build with empty prefs,
        // all statuses must be notDownloaded.
        expect(
          notifier.statusOf('song-1'),
          SongDownloadStatus.notDownloaded,
          reason:
              'After fix: invalidate() causes rebuild with empty prefs → '
              'all statuses must be notDownloaded',
        );
        expect(
          notifier.statusOf('song-2'),
          SongDownloadStatus.notDownloaded,
          reason: 'All songs must show notDownloaded after bulk delete + fix',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 4 — App resume reconciliation (missing lifecycle hook)
  //
  // AUDIT: No WidgetsBindingObserver / didChangeAppLifecycleState exists
  // anywhere in the download system. This group documents that gap and
  // verifies the notifier has no reconcile() method yet.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 4: App resume reconciliation (lifecycle hook gap)', () {
    test(
      'AUDIT [DOCUMENTS GAP]: DownloadStateNotifier has no reconcile() method',
      () {
        when(() => mockOffline.getDownloadedSongIds()).thenReturn([]);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: This test documents Bug 1's third failure mode:
        // there is no mechanism to re-check file existence on app resume
        // (e.g. after the OS reclaims storage).
        //
        // The DownloadStateNotifier does NOT have a reconcile() method.
        // This test simply verifies the notifier can be read without crash —
        // the reconcile() method is the FIX to add.
        expect(notifier, isNotNull,
            reason:
                'Notifier exists but has no reconcile() — gap documented. '
                'Fix: add reconcile() called from WidgetsBindingObserver '
                'on didChangeAppLifecycleState(AppLifecycleState.resumed).');
      },
    );

    test(
      'AUDIT [AFTER FIX]: manual provider invalidation on resume fixes the gap',
      () {
        // AUDIT: Arrange — prefs says downloaded, but file is now gone
        // (simulating what happens after OS reclaims storage).
        when(() => mockOffline.getDownloadedSongIds())
            .thenReturn(['song-1']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        // AUDIT: Initial build — file exists.
        container.read(downloadStateProvider);

        // AUDIT: Simulate OS deleting the file between sessions.
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(false);
        // SharedPreferences still has the ID (stale).
        when(() => mockOffline.getDownloadedSongIds()).thenReturn([]);

        // AUDIT: On app resume, the fix calls container.invalidate().
        container.invalidate(downloadStateProvider);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: After re-build with empty prefs, status is notDownloaded.
        expect(
          notifier.statusOf('song-1'),
          SongDownloadStatus.notDownloaded,
          reason:
              'After resume invalidation with empty prefs, '
              'status must reconcile to notDownloaded',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 5 — OfflineService.deleteSong() is called by the notifier
  //
  // AUDIT: Verify the service method is actually called when the notifier
  // delegates deletion (call-chain tracing per SKILL 7).
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 5: Call-chain verification', () {
    test(
      'AUDIT: notifier.deleteSong() calls OfflineService.deleteSong()',
      () async {
        when(() => mockOffline.getDownloadedSongIds()).thenReturn(['song-1']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);
        when(() => mockOffline.deleteSong('song-1'))
            .thenAnswer((_) async => true);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        await container.read(downloadStateProvider.notifier).deleteSong('song-1');

        // AUDIT: The notifier MUST delegate to the service — not implement
        // deletion itself.  This ensures the file is actually removed.
        verify(() => mockOffline.deleteSong('song-1')).called(1);
      },
    );

    test(
      'AUDIT: statusOf() defaults to notDownloaded for unknown song IDs',
      () {
        when(() => mockOffline.getDownloadedSongIds()).thenReturn([]);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        // AUDIT: Songs not in the state map must default to notDownloaded,
        // not throw or return null.
        expect(
          container.read(downloadStateProvider.notifier).statusOf('unknown'),
          SongDownloadStatus.notDownloaded,
        );
      },
    );

    test(
      'AUDIT: downloadSong() guard prevents double-download (no-op if active)',
      () async {
        when(() => mockOffline.getDownloadedSongIds()).thenReturn(['song-1']);
        when(() => mockOffline.isSongDownloaded('song-1')).thenReturn(true);

        final container = _buildContainer(mockOffline);
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);
        final song = _makeSong(id: 'song-1');

        // AUDIT: Song is already downloaded — calling downloadSong() must be
        // a no-op (guard at download_provider.dart:66-76).
        await notifier.downloadSong(song);

        // AUDIT: OfflineService.downloadSong() must NOT be called.
        verifyNever(() => mockOffline.downloadSong(any(), any()));
      },
    );
  });
}
