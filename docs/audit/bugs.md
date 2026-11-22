# NaviVibe bug audit (read-only)

Branch `feature/search-online`, 2026-11-22. Scope: `lib/` (targeted sweep: providers, services,
sync, polling loops, lifecycle), `android/` manifest, `windows/runner` (nothing found). Rules from
`.claude/skills/navivibe-production/SKILL.md`. No source files were edited and nothing was run;
each finding was confirmed by reading the cited code. **This was a grep-guided sweep of a
105k-line codebase, not a line-by-line read.** The big screens (`now_playing_screen`,
`settings_screen`, `song_table`) and `navi_audio_handler.dart` were only spot-checked.

"Needs device check" means the code path is clear but I did not run it.

---

## HIGH

### 1. `PlayerNotifier.dispose()` disposes the app-wide audio handler (and its just_audio player)
- `lib/providers/player_provider.dart:1712-1724` (`_audioHandler.dispose()`); provider at `:2989-3007`.
- `playerProvider` does `ref.watch(subsonicServiceProvider)`. That provider
  (`settings_provider.dart:425`) is rebuilt whenever server URL, username or password change, which
  rebuilds `playerProvider` and runs the old notifier's `dispose()`. That calls
  `NaviAudioHandler.dispose()` (`navi_audio_handler.dart:1971-1984`: cancels subscriptions,
  `player.stop()`, `player.dispose()`).
- But `audioHandlerProvider` (`:2972-2987`) returns the **global** handler created in `main()`, and a
  comment there says rebuilding "would tear down playback". The new notifier gets a handler whose
  `AudioPlayer` is disposed and whose subscriptions are cancelled.
- Scenario: signed in and playing, the user edits the server URL or switches account in Settings.
  Playback controls and now-playing state go dead until the app restarts. Needs device check
  (depends on whether login/logout also resets providers).
- Fix: don't dispose a handler the notifier doesn't own (only when `audioHandlerProvider` built its
  own fallback), and stop `playerProvider` watching `subsonicServiceProvider` (`ref.read` plus the
  same `ref.listen` used for the handler).

---

## MEDIUM

### 2. Session-sync re-auth path stops retrying after the first failure
- `lib/services/session_sync_service.dart:886-905` (`_scheduleReconnect`, `isAuthFailure && _reconnectAttempt < 3`).
- The timer callback calls `_resolveJwt(forceRefresh: true)`. If the token is null/empty it only logs
  "Re-auth failed" and schedules nothing. If the supplier throws, the exception escapes the `Timer`
  callback (unhandled async error), also with nothing scheduled. `connect()` is never called and the
  spent `_reconnectTimer` is not replaced.
- Scenario: the server closes with 4001 while the JWT endpoint is briefly unreachable (server
  restart, Wi-Fi handover). Sync stays offline until something else calls `connect()` (restart or
  resume); the device silently drops out of "Playing on".
- Fix: wrap the callback in try/catch and fall through to the normal back-off branch
  (`_reconnectAttempt++` + timer) when the token is missing or the supplier throws.

### 3. `connect()` can stay "connecting" on a hung REST resync, blocking every reconnect
- `session_sync_service.dart:722-727`, `:929-936`, guard at `:621-623`; `channel.ready` at `:657`.
- `fetchCurrentState()` uses `_httpClient.get(...)` with no timeout and is awaited inside
  `connect()`; `_isConnecting` clears only in `finally`, and `connect()` returns early while it is
  true. A server that accepts the connection but never answers `/playback/state` holds
  `_isConnecting` for the OS socket timeout (minutes) or longer. If the WebSocket drops meanwhile,
  `_onDisconnected` → `connect()` is a no-op. `channel.ready` is likewise untimed.
- Fix: `.timeout(const Duration(seconds: 10))` on the REST call and on `channel.ready`, or don't
  await the REST resync inside the guarded section.

### 4. A short first page is treated as "end of library" (truncated mirror if a server caps `songCount`)
- `lib/providers/library_provider.dart:415-433`; prune guard `:153-164`.
- The loop requests 500 per page and sets `complete = true` as soon as `chunk.length < pageSize`.
  If a server or proxy caps `search3` `songCount` below 500, page 1 returns e.g. 100, the loop
  declares complete and calls `_markSynced()`, and the mirror holds 100 songs until the next sync
  interval. `_pruneMissing` is protected by the "seen < half of cached" guard, but a fresh install
  has no cache. The duplicate-page `break` (`:424`) also falls through to `_markSynced()` as if the
  sync had succeeded.
- Conditional: Navidrome normally honours the requested size, so check the user's server/proxy.
- Fix: end only on an empty page (the page cap already bounds the loop), advance `offset` by
  `chunk.length`, and skip `_markSynced()` when the duplicate-page guard fires.

### 5. `ref.read(<autoDispose>.future)` with no listener (skill rule 2)
- `lib/features/social/ui/social_widgets.dart:199`: `ref.read(socialUsersProvider.future)`, and
  `socialUsersProvider` is `FutureProvider.autoDispose` (`social_providers.dart:53`).
- The skill documents exactly this as the cause of the unfinished-sync incident. The request here is
  short, so the likely impact is an intermittently failing "add a person" picker rather than corrupted
  data.
- Fix: keep a listener for the duration, as `mascot/chat/chat_controller.dart:189` does with
  `ref.listen(provider, (_, _) {})`, or make the provider keep-alive.

### 6. Online-fetch follow loop has no overall deadline while the server is "transiently" unreachable
- `lib/features/online_fetch/logic/online_fetch_providers.dart:547-560`.
- On `isTransient` errors it does `offline++`, resets `lastChange = now` (so the stall limit never
  fires) and `continue`s. Back-off is capped but there is no total cap: a download whose server is
  gone for days polls forever and the UI keeps showing it in progress. The search poll (`_run`, `:187`)
  does have a `deadline`. The loop does stop on dispose.
- Fix: add an absolute cap (e.g. total time offline) after which `_follow` returns `onGiveUp`.

### 7. `setPlaylistSongs` sends the whole ordered song list in a GET query string
- `lib/services/subsonic_service.dart:711-728`.
- One `songId` parameter per song. Re-saving a large playlist (a few hundred songs) can exceed
  proxy/server URL limits (nginx default 8 KB is roughly 400 ids) and fail with 414/400, surfaced as a
  bare `Exception('setPlaylistSongs HTTP ...')`.
- Fix: send as a POST form body, or batch via `updatePlaylist` `songIdToAdd`.

---

## LOW

### 8. History import writes state after the provider may be gone, and drops non-API errors
- `lib/features/history_import/logic/history_import_providers.dart:113-133`, `_wait` `:141`.
- `ref.onDispose(() => _stop = true)` stops the loop, but after `await api.step(...)` it still sets
  `state` with no `ref.mounted` check, and so does the `finally`. Only `OnlineFetchException` is
  caught; a `FormatException`/socket error leaves the run silently stopped with no message.
- Fix: `if (!ref.mounted) return;` after each await; add a generic `catch` that sets an error.

### 9. Online search shows no error for non-`OnlineFetchException` failures
- `online_fetch_providers.dart:178-228`. Only `OnlineFetchException` is caught, so a `TypeError` from
  a malformed answer leaves the state in the "searching" shape.
- Fix: add a trailing `catch (_)` that sets `base.withResult(error: ...)` if still current.

### 10. `setState` after `await` without `mounted`
- `lib/features/smart_playlists/ui/rule_editor_screen.dart:131-138`
  (`final v = await showChoiceSheet(...); if (v != null) setState(...)`). If the editor closes while the
  sheet is open, `setState` runs on a disposed State (assertion in debug, harmless in release).
- Fix: `if (v != null && mounted)`.

### 11. HTTP calls without a timeout
- `lib/features/status/logic/status_providers.dart:93` (`http.get('/health')`) and
  `lib/features/share/share_sheet.dart:108` (web branch). The Status health row can spin indefinitely
  on a black-holed network.
- Fix: `.timeout(...)`.

### 12. `resetAccount()` clears `_isConnecting` while an old `connect()` is still in flight
- `session_sync_service.dart:1171-1180` versus the old call's `finally` at `:721`. After an account
  switch a new `connect()` can start while the previous one still awaits `channel.ready`. The
  generation check (`:660`) makes the old one bail, but its `finally` then clears `_isConnecting` while
  the new one is mid-flight, allowing an overlapping third connect. The generation guard limits the
  harm to a wasted socket.

---

## Checked and found sound

- Library pagination (`library_provider.dart:415`): page cap 2000, duplicate-page guard, empty-page
  stop. `allSongsProvider` is keep-alive as the skill requires; `_syncInFlight` clears in `finally`.
- `mapBounded` (`utils/bounded_map.dart`) and the play-outbox flush loop terminate.
- `session_sync_service` timers: all cancelled in `disconnect()` / `_onDisconnected`; stale sockets are
  ignored via `identical(_channel, channel)` and `_generation`.
- `PlayerNotifier.dispose()` cancels its own subscriptions and timers (the problem in #1 is only the
  handler disposal).
- Desktop top-bar search field disposes its focus listener, timer and controller.
- `notification_triggers.dart` periodic timers are app-lifetime by design.
- `AndroidManifest.xml`: `usesCleartextTraffic="true"` looks deliberate for self-hosted LAN servers
  (a security note, not a bug); audio_service components are exported as the plugin requires.
- `windows/runner`: nothing relevant found.

## Not covered

`navi_audio_handler.dart` internals (queue/index maths for crossfade and shuffle), the 1,000+ line
screens, `song_table.dart` (uncommitted edits), Drift migrations, `tool/`, and the
`ref.watch(playerProvider)` rebuild-scope issues (performance, another audit's remit).
