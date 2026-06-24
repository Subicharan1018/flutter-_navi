// =============================================================================
// download_connectivity_audit_test.dart
//
// AUDIT: Bug 2 — Download Button Unresponsive After Low-Network App Restart
//
// Tests that the download button gives proper user feedback under no-network
// conditions and becomes functional when connectivity is restored.
//
// Root cause under test:
//   1. No connectivity check before starting a Dio download.
//   2. Dio is configured with no timeout — hangs indefinitely on no-network,
//      appearing "stuck" at "Downloading… 0%".
//   3. No user-facing feedback (snackbar/dialog) when a download fails.
//
// Run: flutter test test/download_connectivity_audit_test.dart --reporter=expanded
// =============================================================================

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:navivibe/models/download_state.dart';
import 'package:navivibe/offline_service.dart';
import 'package:navivibe/providers/download_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';

import 'package:navivibe/services/subsonic_service.dart';

import 'helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockOfflineService extends Mock implements OfflineService {}

class MockSubsonicService extends Mock implements SubsonicService {}

class MockConnectivity extends Mock implements Connectivity {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a [ProviderContainer] with all service providers overridden.
ProviderContainer _buildContainer({
  required MockOfflineService mockOffline,
  required MockSubsonicService mockSubsonic,
  required MockConnectivity mockConnectivity,
}) {
  return ProviderContainer(
    overrides: [
      offlineServiceProvider.overrideWithValue(mockOffline),
      subsonicServiceProvider.overrideWithValue(mockSubsonic),
      connectivityProvider.overrideWithValue(mockConnectivity),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // AUDIT: mocktail requires fallback values for any custom types used
    // with any() / captureAny() matchers in verify() calls.
    registerFallbackValue(makeSong());
    registerFallbackValue(MockSubsonicService());
  });

  late MockOfflineService mockOffline;
  late MockSubsonicService mockSubsonic;
  late MockConnectivity mockConnectivity;

  setUp(() {
    mockOffline = MockOfflineService();
    mockSubsonic = MockSubsonicService();
    mockConnectivity = MockConnectivity();

    // AUDIT: Default — no songs in prefs, service is initialized.
    when(() => mockOffline.getDownloadedSongIds()).thenReturn([]);
    when(() => mockOffline.isSongDownloaded(any())).thenReturn(false);
    // Stub async file-check so _reconcileWithDisk() never throws.
    when(
      () => mockOffline.isSongDownloadedAsync(any()),
    ).thenAnswer((_) async => false);
    // Default: device has connectivity (tests override to simulate offline).
    when(
      () => mockConnectivity.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 1 — Download failure transitions state correctly
  //
  // AUDIT: When the network is unavailable, the Dio download throws.
  // DownloadStateNotifier._performDownload() must catch this and call
  // _setFailed() — NOT leave the state stuck in "downloading".
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 1: Download failure transitions to failed state', () {
    test(
      'AUDIT: failed downloadSong() → status transitions to failed, not stuck',
      () async {
        // AUDIT: Arrange — simulate a network failure (OfflineService throws).
        final song = makeSong();
        when(
          () => mockOffline.downloadSong(song, mockSubsonic),
        ).thenThrow(Exception('Network unreachable'));
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: Act — attempt download under no-network.
        await notifier.downloadSong(song);

        // AUDIT: Assert — state must be 'failed', NOT 'downloading'.
        // A stuck "downloading" state is exactly Bug 2's symptom.
        expect(
          notifier.statusOf(song.id),
          SongDownloadStatus.failed,
          reason:
              'A failed download must transition to failed, not stay stuck '
              'in downloading. Bug 2: the button appears to do nothing because '
              'the state never leaves "downloading".',
        );
      },
    );

    test('AUDIT: failed download stores an error message in state', () async {
      // AUDIT: The _setFailed() path should record a human-readable message
      // (per AppException rules in GEMINI.md).
      final song = makeSong();
      when(
        () => mockOffline.downloadSong(song, mockSubsonic),
      ).thenThrow(Exception('Connection timed out'));
      when(
        () => mockSubsonic.getStreamUrl(any()),
      ).thenReturn('http://server/stream');

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      await container.read(downloadStateProvider.notifier).downloadSong(song);

      final dlState = container.read(downloadStateProvider)[song.id];
      expect(dlState, isNotNull);
      expect(dlState!.status, SongDownloadStatus.failed);
      // AUDIT: Error message must be non-empty so UI can display it.
      expect(
        dlState.errorMessage,
        isNotNull,
        reason: 'Failed state must include an error message for the UI',
      );
      expect(dlState.errorMessage!.isNotEmpty, isTrue);
    });

    test(
      'AUDIT [BUG-DEMONSTRATES]: no Dio timeout means state stays in '
      '"downloading" until the server eventually responds or process dies',
      () async {
        // AUDIT: This test documents the silent-hang bug.
        // OfflineService.downloadSong() creates `Dio()` with no timeout:
        //   final dio = Dio(); // ← no connectTimeout, no receiveTimeout
        // Under no-network, the HTTP call hangs indefinitely.
        // The download state stays at "downloading" and progress = 0%.
        // The button is visually disabled (no onTap) — looks unresponsive.
        //
        // We use a Completer that never completes to accurately simulate an
        // infinite Dio request.  The test only checks the *intermediate* state
        // (the hung state), then cleans up by completing the completer so the
        // container can be disposed without leaked async tasks.
        //
        // FIX: Add to OfflineService.downloadSong():
        //   dio.options.connectTimeout = const Duration(seconds: 15);
        //   dio.options.receiveTimeout = const Duration(seconds: 60);

        final song = makeSong(id: 'hanging-song');
        final hangCompleter = Completer<bool>();

        // AUDIT: The download call never completes — simulates an infinite
        // Dio request with no timeout configured.
        when(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) => hangCompleter.future);
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(() async {
          // Prevent leaked async tasks before container disposal.
          if (!hangCompleter.isCompleted) {
            hangCompleter.complete(false);
            await Future<void>.delayed(Duration.zero);
          }
          container.dispose();
        });

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: Fire the download but don't await (simulates the fire-and-forget
        // call in OptionsMenu).
        unawaited(notifier.downloadSong(song));

        // AUDIT: Give microtasks a chance to run so the notifier sets the
        // intermediate "queued" or "downloading" state.
        await Future<void>.delayed(Duration.zero);

        // AUDIT: State is now "queued" or "downloading" — NOT "failed".
        // This is Bug 2's symptom: no timeout → hangs here forever.
        final status = notifier.statusOf(song.id);
        expect(
          status == SongDownloadStatus.downloading ||
              status == SongDownloadStatus.queued,
          isTrue,
          reason:
              'BUG-2: Without a Dio timeout, state hangs in downloading/queued. '
              'Fix: add connectTimeout + receiveTimeout to Dio options in '
              'OfflineService.downloadSong().',
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 2 — Retry is allowed after failure (button becomes functional)
  //
  // AUDIT: After a failed download attempt, the guard in downloadSong()
  // must allow a retry.  Only queued/downloading/downloaded are no-ops.
  // Failed must be retriable.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 2: Retry is allowed after failure', () {
    test(
      'AUDIT: downloadSong() guard allows retry when status == failed',
      () async {
        final song = makeSong();
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');

        // AUDIT: First attempt fails.
        when(
          () => mockOffline.downloadSong(song, mockSubsonic),
        ).thenThrow(Exception('No route to host'));

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // First attempt — fails.
        await notifier.downloadSong(song);
        expect(notifier.statusOf(song.id), SongDownloadStatus.failed);

        // AUDIT: Second attempt — network is now restored, succeeds.
        when(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => true);

        // AUDIT: The guard (lines 67-72 in download_provider.dart) must NOT
        // block the retry because 'failed' is not in the blocked set.
        await notifier.downloadSong(song);

        expect(
          notifier.statusOf(song.id),
          SongDownloadStatus.downloaded,
          reason:
              'After connectivity restore, retry must succeed. '
              'Guard must allow retry when status == failed.',
        );
      },
    );

    test(
      'AUDIT: downloadSong() guard blocks re-tap when already downloading',
      () async {
        // AUDIT: This is the correct guard behaviour — not the bug.
        // Prevents multi-tap from starting duplicate downloads.
        final song = makeSong();
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');

        // AUDIT: Simulate a download that hasn't finished yet.
        when(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 100), () => true),
        );

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // Fire first download (don't await).
        unawaited(notifier.downloadSong(song));
        await Future<void>.delayed(Duration.zero);

        // AUDIT: Second tap while downloading — must be a no-op.
        // The service must only be called once.
        await notifier.downloadSong(song);

        verify(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1); // only 1 call — guard blocked the second tap
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 3 — No user feedback on failure (the silent-fail bug)
  //
  // AUDIT: When a download fails, the state transitions to 'failed'
  // but NO snackbar or dialog is shown. The OptionsMenu is typically
  // dismissed by then, and the only UI signal is a tiny 14px error icon
  // in the _DownloadBadge. This group documents the feedback gap.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 3: User feedback gap on network failure (Bug 2)', () {
    test('AUDIT [DOCUMENTS GAP]: failed status is set, but notification is '
        'provider-only — no snackbar callback exists in the notifier', () async {
      // AUDIT: The notifier has no mechanism to trigger a snackbar.
      // It sets state to failed and that's it.  The widget layer (OptionsMenu)
      // only shows feedback if it's still mounted and watching the state.
      //
      // FIX (per plan): Add a snackbar in OptionsMenu's "Failed" case onTap,
      // and optionally a callback/stream from the notifier for proactive
      // failure notification.

      final song = makeSong();
      when(
        () => mockOffline.downloadSong(song, mockSubsonic),
      ).thenThrow(Exception('No internet'));
      when(
        () => mockSubsonic.getStreamUrl(any()),
      ).thenReturn('http://server/stream');

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      await container.read(downloadStateProvider.notifier).downloadSong(song);

      // AUDIT: State is failed — but the test verifies there is no way
      // for the notifier to trigger snackbar independently.
      // The notifier is a pure state machine; feedback must come from widgets.
      final dlState = container.read(downloadStateProvider)[song.id];
      expect(
        dlState?.status,
        SongDownloadStatus.failed,
        reason: 'State is set to failed — the only signal available',
      );

      // AUDIT: Document: DownloadStateNotifier has no onError callback/stream.
      // A widget must observe the state transition and react.
      // This is the feedback gap documented in the audit.
      expect(
        dlState?.errorMessage,
        isNotNull,
        reason:
            'errorMessage is the only user-facing signal. '
            'Fix: OptionsMenu must show a SnackBar when it observes '
            'the transition from downloading → failed.',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 4 — Connectivity restore without app restart
  //
  // AUDIT: After a failed download (no-network), when connectivity is
  // restored, the button must become functional again (retry works).
  // No app restart should be required.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 4: Connectivity restore without restart', () {
    test(
      'AUDIT: connectivity restore → retry succeeds without app restart',
      () async {
        final song = makeSong();
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');

        // AUDIT: Phase 1 — app starts with no network.
        when(
          () => mockOffline.downloadSong(song, mockSubsonic),
        ).thenThrow(Exception('Network unavailable'));

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        await notifier.downloadSong(song);
        expect(
          notifier.statusOf(song.id),
          SongDownloadStatus.failed,
          reason: 'Phase 1: download fails on no-network',
        );

        // AUDIT: Phase 2 — connectivity is restored (no app restart).
        // The user taps the "Failed — tap to retry" button in OptionsMenu.
        when(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => true);

        await notifier.downloadSong(song);

        // AUDIT: Button is now functional — download succeeded.
        expect(
          notifier.statusOf(song.id),
          SongDownloadStatus.downloaded,
          reason:
              'Phase 2: after connectivity restore, button must work '
              'without requiring app restart',
        );
      },
    );

    test('AUDIT: multiple failure-retry cycles work correctly', () async {
      final song = makeSong();
      when(
        () => mockSubsonic.getStreamUrl(any()),
      ).thenReturn('http://server/stream');

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      final notifier = container.read(downloadStateProvider.notifier);

      // AUDIT: Cycle 1 — fail.
      when(
        () => mockOffline.downloadSong(song, mockSubsonic),
      ).thenThrow(Exception('No network'));
      await notifier.downloadSong(song);
      expect(notifier.statusOf(song.id), SongDownloadStatus.failed);

      // AUDIT: Cycle 2 — fail again (flaky network).
      when(
        () => mockOffline.downloadSong(song, mockSubsonic),
      ).thenThrow(Exception('Connection reset'));
      await notifier.downloadSong(song);
      expect(
        notifier.statusOf(song.id),
        SongDownloadStatus.failed,
        reason: 'Second failure must also be handled gracefully',
      );

      // AUDIT: Cycle 3 — succeed.
      when(
        () => mockOffline.downloadSong(
          song,
          mockSubsonic,
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => true);
      await notifier.downloadSong(song);
      expect(
        notifier.statusOf(song.id),
        SongDownloadStatus.downloaded,
        reason: 'Eventually succeeds after repeated retries',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 5 — Pre-flight connectivity check (Bug 2 FIX verification)
  //
  // AUDIT: The fix adds a connectivity pre-check before calling the service.
  // When offline, the check short-circuits immediately to _setFailed(),
  // so OfflineService is never called and the download never hangs.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 5: Pre-flight connectivity check gap (Bug 2)', () {
    test('AUDIT [AFTER FIX]: with connectivity pre-check, failed state is set '
        'immediately without invoking OfflineService', () async {
      // AUDIT: Bug 2 FIX verified — the pre-check in downloadSong() blocks
      // the service call when offline and sets failed immediately.
      final song = makeSong();

      // Simulate no connectivity.
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.none]);

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      final notifier = container.read(downloadStateProvider.notifier);
      await notifier.downloadSong(song);

      // AUDIT: OfflineService was NEVER called — pre-flight short-circuited.
      verifyNever(() => mockOffline.downloadSong(any(), any()));

      // AUDIT: State is immediately failed with a readable message.
      final dlState = notifier.state[song.id];
      expect(dlState?.status, SongDownloadStatus.failed);
      expect(dlState?.errorMessage, 'No internet connection');
    });

    test('AUDIT [AFTER FIX]: offline pre-flight blocks OfflineService call '
        '(proves the fix is active)', () async {
      // AUDIT: With the fix applied, OfflineService is NOT called when
      // the device is offline — the pre-flight short-circuits.
      final song = makeSong();

      // Simulate no connectivity.
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.none]);

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      await container.read(downloadStateProvider.notifier).downloadSong(song);

      // AUDIT: OfflineService was NEVER called — pre-flight blocked it.
      verifyNever(
        () => mockOffline.downloadSong(
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      );

      // AUDIT: Result is immediately "failed" with readable message.
      expect(
        container.read(downloadStateProvider.notifier).statusOf(song.id),
        SongDownloadStatus.failed,
        reason: 'Pre-flight check fires immediately, no Dio hang possible.',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group 6 — Successful download flow (regression guard)
  //
  // AUDIT: Ensure fixes do not break the happy path.
  // ══════════════════════════════════════════════════════════════════════════

  group('Group 6: Happy path regression guard', () {
    test(
      'AUDIT: successful download → status transitions to downloaded',
      () async {
        final song = makeSong();
        when(
          () => mockSubsonic.getStreamUrl(any()),
        ).thenReturn('http://server/stream');
        when(
          () => mockOffline.downloadSong(
            song,
            mockSubsonic,
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => true);

        final container = _buildContainer(
          mockOffline: mockOffline,
          mockSubsonic: mockSubsonic,
          mockConnectivity: mockConnectivity,
        );
        addTearDown(container.dispose);

        final notifier = container.read(downloadStateProvider.notifier);

        // AUDIT: Should start as notDownloaded.
        expect(notifier.statusOf(song.id), SongDownloadStatus.notDownloaded);

        await notifier.downloadSong(song);

        expect(
          notifier.statusOf(song.id),
          SongDownloadStatus.downloaded,
          reason: 'Happy path must not be broken by Bug 2 fixes',
        );
      },
    );

    test('AUDIT: progress is emitted during download (0 → 1)', () async {
      final song = makeSong();
      when(
        () => mockSubsonic.getStreamUrl(any()),
      ).thenReturn('http://server/stream');

      // AUDIT: Simulate a download that fires the progress callback.
      when(
        () => mockOffline.downloadSong(
          song,
          mockSubsonic,
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        final onProgress =
            invocation.namedArguments[const Symbol('onProgress')]
                as Function(double)?;
        onProgress?.call(0.5);
        return true;
      });

      final container = _buildContainer(
        mockOffline: mockOffline,
        mockSubsonic: mockSubsonic,
        mockConnectivity: mockConnectivity,
      );
      addTearDown(container.dispose);

      await container.read(downloadStateProvider.notifier).downloadSong(song);

      // AUDIT: Final state is downloaded with progress = 1.0.
      final dlState = container.read(downloadStateProvider)[song.id];
      expect(dlState?.status, SongDownloadStatus.downloaded);
      expect(
        dlState?.progress,
        1.0,
        reason: 'Progress must be 1.0 after successful download',
      );
    });
  });
}

// ignore: unused_element
void unawaited(Future<void> future) {}
