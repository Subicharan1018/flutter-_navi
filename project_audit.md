# Flutter Project Audit Report

## 1. CODE QUALITY
[🟡 MEDIUM] CODE QUALITY — Magic numbers for history length
File: `lib/providers/player_provider.dart` | Location: `PlayerState` (~line 26)
Problem: `maxHistoryLength = 50` is hardcoded directly into the state class.
Fix: Extract this to an app-level configuration constant or allow it to be injected via settings.

[FIXED] [🟠 HIGH] CODE QUALITY — Swallowed exceptions in audio control
File: `lib/providers/player_provider.dart` | Location: `PlayerNotifier.playNext` (~line 466)
Problem: A bare `catch (_)` swallows `player.seekToNext()` errors without logging, making playback failures untraceable.
Fix: Log the exception via a proper logging service before executing the fallback `_jumpToInternal` block.

## 2. ARCHITECTURE & DESIGN
[FIXED] [🟠 HIGH] ARCHITECTURE & DESIGN — Service call directly from UI widget
File: `lib/widgets/add_to_playlist_dialog.dart` | Location: `_AddToPlaylistDialogState._createAndAdd` (~line 39)
Problem: The UI widget reads the `subsonicServiceProvider` directly to execute `service.createPlaylist()`, violating the separation of concerns.
Fix: Delegate playlist creation to a dedicated Riverpod provider or repository method (e.g. `ref.read(playlistControllerProvider).createAndAdd(...)`).

[FIXED] [🟠 HIGH] ARCHITECTURE & DESIGN — Provider read inside build delegate
File: `lib/screens/library_screen.dart` | Location: `_LibraryScreenState._buildItem` (~line 242)
Problem: `ref.read(subsonicServiceProvider)` is called repeatedly inside a lazy `SliverChildBuilderDelegate` build loop, which is a Riverpod anti-pattern.
Fix: Hoist the service reference by using `ref.watch(subsonicServiceProvider)` at the top of the main `build()` method and pass it into `_buildItem`.

## 3. PERFORMANCE
[FIXED] [🔴 CRITICAL] PERFORMANCE — Main thread blocked by image processing
File: `lib/screens/now_playing_screen.dart` | Location: `_extractPaletteIsolate` (~line 29)
Problem: Despite the function name, `PaletteGenerator.fromImageProvider` is executed synchronously on the UI thread, causing severe jank during song transitions.
Fix: Offload the image decoding and palette extraction to a background thread using `compute()` or `Isolate.run()`.

[FIXED] [🔴 CRITICAL] PERFORMANCE — Post-frame rebuild loop on scroll
File: `lib/screens/library_screen.dart` | Location: `_LibraryScreenState.build` (~line 154-159)
Problem: `setState(() => _listAnimated = true)` is called inside `addPostFrameCallback` deep within a lazy list builder, triggering unpredictable global screen rebuilds while the user scrolls.
Fix: Manage the animation state locally within a dedicated `StatefulWidget` for the list tile, avoiding global `LibraryScreen` rebuilds.

## 4. AUDIO / PLAYBACK SPECIFIC
[FIXED] [🟠 HIGH] AUDIO / PLAYBACK SPECIFIC — Missing queue lock on navigation
File: `lib/providers/player_provider.dart` | Location: `PlayerNotifier.playNext` (~line 444)
Problem: Unlike `setQueue` and `playPlaylist`, `playNext` and `playPrev` do not await the `_queueOpLock`, creating race conditions if a user skips tracks rapidly while the queue is mutating.
Fix: Add `await _queueOpLock?.future;` at the top of `playNext` and `playPrev`.

## 5. UI / UX
[🟡 MEDIUM] UI / UX — Hardcoded colors bypassing theme tokens
File: `lib/widgets/add_to_playlist_dialog.dart` | Location: `_AddToPlaylistDialogState._createAndAdd` (~line 64, 141)
Problem: `Colors.black` is hardcoded for `SnackBar` text styling instead of utilizing the dynamic `ThemeTokens` system.
Fix: Use `ThemeTokens.of(context).textPrimary` or `bgBase` depending on contrast needs.

[🟡 MEDIUM] UI / UX — Missing proper error states
File: `lib/widgets/add_to_playlist_dialog.dart` | Location: `_AddToPlaylistDialogState.build` (~line 331)
Problem: The playlist fetch error state simply shows a generic `ListTile` with a red error icon, providing no context or retry mechanism for the user.
Fix: Implement a clear "Failed to load playlists" state with a retry button.

## 6. DATA & PERSISTENCE
[🟡 MEDIUM] DATA & PERSISTENCE — Undebounced Hive writes
File: `lib/services/transcoding_service.dart` | Location: `TranscodingService.setWifiBitrate` (~line 162-172)
Problem: `HiveBoxes.audio.put` is called immediately on every state update. If hooked up to a UI slider, this would hammer the persistence layer.
Fix: Implement a debouncer (e.g. `Timer`) to batch frequent persistence writes.

## 7. SECURITY
[FIXED] [🔴 CRITICAL] SECURITY — Hardcoded fallback credentials
File: `lib/services/subsonic_service.dart` | Location: `_webDavUploadStream` (~line 749-750)
Problem: The WebDAV uploader falls back to using hardcoded 'casaos' strings for both username and password if none are provided.
Fix: Throw an `AuthException` or strictly require explicit user configuration instead of defaulting to easily guessable credentials.

[FIXED] [🟠 HIGH] SECURITY — Sensitive URLs in production logs
File: `lib/services/subsonic_service.dart` | Location: `_webDavUploadStream` (~line 753)
Problem: `debugPrint` logs the full `uri` which may expose authentication tokens, salts, or internal server directory paths in system logs.
Fix: Sanitize the URI before logging by masking query parameters, or remove the log statement entirely.

## 8. TESTABILITY
[FIXED] [🟠 HIGH] TESTABILITY — Hardcoded HTTP Client dependency
File: `lib/services/subsonic_service.dart` | Location: `SubsonicService` properties (~line 26)
Problem: `_client` is initialized directly as `http.Client()`, making it impossible to inject a mock HTTP client for unit testing API responses.
Fix: Inject the HTTP client via the constructor: `SubsonicService({required http.Client client, ...})`.

════════════════════════════════════════════════════
SUMMARY TABLE
════════════════════════════════════════════════════

| File | Critical | High | Medium | Low | Top Priority Fix |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `now_playing_screen.dart` | 1 | 0 | 0 | 0 | Offload palette extraction to Isolate |
| `library_screen.dart` | 1 | 1 | 0 | 0 | Remove post-frame global setState loop |
| `subsonic_service.dart` | 1 | 2 | 0 | 0 | Remove hardcoded fallback credentials |
| `player_provider.dart` | 0 | 2 | 1 | 0 | Add lock to `playNext` / `playPrev` |
| `add_to_playlist_dialog.dart` | 0 | 1 | 2 | 0 | Decouple Subsonic network calls from UI |
| `transcoding_service.dart` | 0 | 0 | 1 | 0 | Debounce Hive writes for bitrates |

════════════════════════════════════════════════════
PRIORITISED ACTION LIST
════════════════════════════════════════════════════

1. **[FIXED]** **[S] Remove hardcoded credentials** (`subsonic_service.dart`) — Critical security risk. Remove the 'casaos' defaults immediately.
2. **[FIXED]** **[M] Offload Palette Extraction** (`now_playing_screen.dart`) — Massive UI jank on song change. Fix by using `compute()` for image processing.
3. **[FIXED]** **[M] Remove Post-Frame Rebuild Loop** (`library_screen.dart`) — Causes intense scroll hitching. Handle animation state inside local widgets.
4. **[FIXED]** **[S] Add Queue Mutex to Track Skips** (`player_provider.dart`) — Prevents race conditions when user rapidly taps Next/Prev during async queue ops.
5. **[FIXED]** **[S] Inject HTTP Client** (`subsonic_service.dart`) — Essential for enabling offline unit testing of the API layer.
6. **[FIXED]** **[M] Refactor UI Network Calls** (`add_to_playlist_dialog.dart`) — Move the `createPlaylist` and list invalidation logic to a dedicated Provider.
7. **[FIXED]** **[S] Sanitize URI Logging** (`subsonic_service.dart`) — Remove or mask the `debugPrint` statement exposing the WebDAV URLs.
8. **[FIXED]** **[S] Log Player Exceptions** (`player_provider.dart`) — Add proper logging inside the bare `catch (_)` blocks in `playNext`.
9. **[S] Fix Hardcoded Dialog Colors** (`add_to_playlist_dialog.dart`) — Replace `Colors.black` and `Colors.redAccent` with proper ThemeTokens.
10. **[S] Debounce Transcoding Writes** (`transcoding_service.dart`) — Add a timer debounce to prevent storage trashing from frequent setting updates.
