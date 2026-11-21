# Performance and "stuck" audit — 2026-11

Scope: background CPU, late input on Windows, playback/loading stuck with a working connection.
Method: code reading of every timer/poller/stream, HTTP client and the Windows single-source bridge.
Not done: no `flutter run --profile` / DevTools capture on a device (no timeline numbers below — see "Not measured").

## Ranked findings

| # | Finding | Evidence | Status |
|---|---------|----------|--------|
| 1 | **Subsonic reads had no retry.** After sleep / network change the pooled keep-alive socket is dead; the first request fails or waits the full 20 s although the server is fine. Every list/home/search call looks "stuck". | `SubsonicService._get` — single `.get().timeout(20s)` | **Fixed**: one retry (12 s) on `SocketException`, `ClientException`, `TimeoutException`; HTTP 401/5xx never retried. `test/services/subsonic_retry_test.dart` (red → green). |
| 2 | **Mobile `setAudioSource` had no timeout inside `_queueLock`.** A hung connection held the lock forever: every later play/skip/queue edit queued behind it. (`AsyncLock` itself always releases in `finally` — verified.) | `NaviAudioHandler._rebuildSource`; desktop path already had 15 s | **Fixed**: 30 s timeout → `TimeoutException`; the existing stuck-recovery handles it. |
| 3 | Desktop load timeout (15 s) skips to the next track (`_handleDesktopLoadError`) — a slow server first byte on Windows skips songs. | `_desktopLoadTrack` | Open — behaviour choice; consider retry-once before skipping. |
| 4 | `_recoverStuckPlayer` marks success even when `_desktopLoadTrack` swallowed an error internally, resetting `_lastFailedIndex` (can loop on a bad track every 45 s). | `navi_audio_handler.dart` ~1862 | Open — needs `_desktopLoadTrack` to report success. Small, in the media-session owner's file. |
| 5 | Always-on timers, all intentional and cheap: position push 7 s (only while playing), persist 2 s debounce (a single Hive put), WS ping 25 s, social people poll 60 s (only with social + alerts), invitation poll (`notification_triggers`, always when social on), Jam 1 s (only in a Jam). None pause when the window is hidden. | grep of `Timer.periodic` | Open — invitation + people polls could skip while `AppLifecycleState.hidden` and playback paused; products decision (alerts need background). |
| 6 | Animation tickers are not a background cost: Flutter stops frames on `hidden`/`paused`, and Microduck already gates on lifecycle. `ArtworkField` / `NowPlayingBars` only repeat while visible. | `lib/core/motion.dart`, `microduck.dart` | No change needed. |
| 7 | Whole-state `ref.watch(playerProvider)` — none remain (grep count 0). | grep | No change needed. |
| 8 | Window/tray services do disk writes (Hive `putAll`) on every resize/move event, unthrottled. Likely contributor to resize jank on Windows. | `WindowManagerService._saveWindowState` | Open — debounce 300 ms (not done; needs a Windows run to verify). |

## Not measured
No profile-mode timeline, CPU or rebuild counts were captured; the numbers the task asked for (frames, CPU, rebuilds) are therefore absent rather than estimated. Next step: `flutter run --profile -d windows`, DevTools Performance tab while idle-minimised for 5 min, and while scrolling Home.

## Verification
`flutter analyze`: 7 infos (all `tool/*.dart` avoid_print, pre-existing), 0 errors/warnings. `flutter test`: 1848 passed, 2 skipped, 0 failed.
