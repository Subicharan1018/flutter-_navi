# 🔴 NAVIVIBE — ISSUES & RACE CONDITIONS

> Comprehensive audit of all known bugs, UX problems, and race conditions  
> across the NaviVibe Flutter codebase.

---

## SECTION 1: GENERAL ISSUES

### ISSUE-1: Theme Not Applying to All Screens

**Problem:** The dynamic `ThemeTokens` system (`InheritedWidget`) is implemented in `theme.dart`, but **17 out of 20 UI files** bypass it entirely and hardcode legacy `AppTheme.*` static constants (`AppTheme.coreBackground`, `AppTheme.textPrimary`, `Colors.black`, etc.).

**Affected Files:**
| File | Uses `ThemeTokens.of(context)` | Uses Hardcoded `AppTheme.*` |
|---|---|---|
| `app_scaffold.dart` | ✅ Yes | ❌ No |
| `song_tile.dart` | ✅ Yes | ❌ No |
| `home_screen.dart` | ✅ Partial | ⚠️ Partial |
| `settings_screen.dart` | ✅ Partial | ⚠️ Partial |
| `playlist_details_screen.dart` | ✅ Partial | ⚠️ Partial |
| `now_playing_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `mini_player.dart` | ❌ No | ✅ Hardcoded everywhere |
| `add_to_playlist_dialog.dart` | ❌ No | ✅ Hardcoded everywhere |
| `library_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `search_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `edit_playlist_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `song_picker_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `favorites_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `queue_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `replay_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `options_menu.dart` | ❌ No | ✅ Hardcoded everywhere |
| `create_playlist_dialog.dart` | ❌ No | ✅ Hardcoded everywhere |
| `album_card.dart` | ❌ No | ✅ Hardcoded everywhere |
| `made_for_you_screen.dart` | ❌ No | ✅ Hardcoded everywhere |
| `new_releases_screen.dart` | ❌ No | ✅ Hardcoded everywhere |

**Root Cause:** The ThemeTokens system was added *after* most screens were written, and only a handful of files were migrated. When the user switches to Neumorphic, Zen, Analog, or Frost — those screens still render with Spotify's black/green palette.

**Impact:** Severe — Theme switching is essentially broken on ~85% of the app.

---

### ISSUE-2: Shuffle Lag While Song Is Playing

**Problem:** When the user toggles shuffle while a song is playing, there is a perceptible lag/stutter because:
1. `applyShuffleAlgorithm()` introduces an artificial `Future.delayed(50ms)` (line 556)
2. The shuffle computation runs on a background isolate via `compute()` (correct), but `_updateQueueAfterAnchor()` then performs a **full audio source rebuild** — `setAudioSource()` resets the entire ConcatenatingAudioSource, causing just_audio to momentarily stop buffering the current track.
3. The position must be saved/restored which introduces an audible gap.

**Location:** `lib/providers/player_provider.dart:553-577` + `lib/services/audio_handler.dart:221-227`

**Impact:** Medium — audible stutter/gap every time shuffle is toggled mid-playback.

---

### ISSUE-3: UX of Adding Songs to a Playlist (Click-to-Add Without Confirmation)

**Problem:** In `AddToPlaylistDialog`, clicking a playlist row **immediately** toggles the song in/out of the playlist via a network API call. There is no "select songs → confirm with Save" flow. Additionally, `SongPickerScreen` has the same instant-add behavior with no undo mechanism.

**User Expectation:** Checkboxes should be selectable/deselectable freely, and changes should only be committed when the user clicks "Save" or "Done".

**Current Behavior:**
- Tap a playlist → API call fires immediately (add)
- Tap again → API call fires immediately (remove)
- No batch operation, no undo on `SongPickerScreen`
- Accidental taps cause irreversible server-side mutations

**Location:** `lib/widgets/add_to_playlist_dialog.dart:79-143` and `lib/screens/song_picker_screen.dart:141-158`

**Impact:** Medium UX — frustrating for users managing large playlists.

---

## SECTION 2: RACE CONDITIONS (CONCURRENCY & ASYNC CONFLICTS ONLY)

---

### RC-1: Shuffle State vs. Stream Listener Race

**Trigger:** User rapidly toggles shuffle on/off  
**Location:** `player_provider.dart:531-577`

**Mechanism:**  
1. `setShuffleMode(true)` sets `state.shuffleMode = true` **synchronously** (L532), then calls `applyShuffleAlgorithm()` which is async.
2. User immediately taps again → `setShuffleMode(false)` sets `state.shuffleMode = false`, then calls `unshuffleQueue()`.
3. Both `applyShuffleAlgorithm()` and `unshuffleQueue()` are now in-flight simultaneously.
4. `_isShuffling` is set to `true` by both, but `finally` blocks race — the first to complete sets `_isShuffling = false`, leaving the second running without the guard flag.
5. Both call `_updateQueueAfterAnchor()` which calls `player.setAudioSource()` — two concurrent `setAudioSource()` calls on the same `AudioPlayer` instance cause undefined behavior (just_audio throws or silently loses one call).

**Result:** Queue order corruption, wrong song plays, or silent crash.

---

### RC-2: Autoplay Double-Fetch Race (Partially Mitigated but Still Possible)

**Trigger:** Song reaches second-to-last position in queue while processingState also transitions to `completed`.  
**Location:** `player_provider.dart:214-266`

**Mechanism:**  
1. `currentIndexStream` fires when index reaches `queueLen - 2` → calls `_triggerAutoplayIfNeeded()` (L216-218)
2. Nearly simultaneously, `processingStateStream` fires `ProcessingState.completed` → also calls `_triggerAutoplayIfNeeded()` (L262)
3. The `_isFetchingSimilar` boolean guard (L636) is **not atomic** — both listeners read it as `false` before either sets it to `true`.
4. Although the `_autoplayTriggeredFor` Set adds a second guard, both calls read `lastSong.id` before either writes to the Set, so both proceed past the guard.

**Result:** Two concurrent `_fetchAndAppendSimilar()` calls → duplicate songs appended, double `player.seek()` calls causing index confusion.

---

### RC-3: Queue Mutation vs. Index Stream Desynchronization

**Trigger:** `addToQueue()`, `removeFromQueue()`, or `reorderQueue()` called while `currentIndexStream` listener fires.  
**Location:** `player_provider.dart:154-228` vs `467-501`

**Mechanism:**  
1. `removeFromQueue(index)` modifies `state.queue` and calls `_audioHandler.removeFromQueue(index)` (L473-483).
2. `_audioHandler.removeFromQueue()` calls `_playlist!.removeAt(index)` which triggers just_audio to emit a new `currentIndex` via `currentIndexStream`.
3. The stream listener at L154 reads `state.queue` to access `state.queue[index]` — but the state was already modified at L481 with the item removed.
4. If the removed index was *before* the current index, the listener's `index` value is off-by-one relative to the new queue contents.

**Result:** `_lastKnownIndex` points to the wrong song. Analytics events record the wrong song. History pushes the wrong song.

---

### RC-4: `toggleStar()` Optimistic UI vs. Network Failure Desync

**Trigger:** Network request to `star`/`unstar` fails after UI state already flipped.  
**Location:** `player_provider.dart:503-524`

**Mechanism:**  
1. `toggleStar()` reads `currentlyStarred` from state (L504).
2. If `currentlyStarred` is true, it **awaits** `_subsonicService.unstar(songId)` (L506) — if this throws, the function exits without updating state. ✅ This is correct.
3. However, if the user calls `toggleStar()` again rapidly before the first `await` completes, the second call reads the **same** state (still starred), fires a second `unstar()` call, and the first call's state update at L507-514 races with the second call's read.
4. Both calls see `currentlyStarred = true` and both fire `unstar()`. When both complete, the state is updated twice with the same removal — no crash, but if either call fails the state is left inconsistent.

**Result:** Star state out of sync with server. UI shows starred but server has unstarred, or vice versa.

---

### RC-5: `allSongsProvider` Stale-While-Revalidate Background Refresh Has No State Update Path

**Trigger:** App opens, cached songs are returned, background refresh completes with different data.  
**Location:** `library_provider.dart:130-136`

**Mechanism:**  
1. `allSongsProvider` returns cached songs immediately from SQLite (L131-136).
2. A fire-and-forget `service.getAllSongs().then(...)` updates the SQLite cache in the background (L132-135).
3. The provider **never** re-emits the fresh data to Riverpod — `ref.keepAlive()` means the provider is not re-executed, and the `.then()` closure doesn't call `ref.invalidateSelf()`.
4. The UI continues showing stale data until the app is restarted or the provider is manually invalidated.

**Result:** Library list shows outdated songs until next cold start. New songs added on the server are invisible for the entire session.

---

### RC-6: `_backgroundRefreshPlaylist()` Fire-and-Forget Race with `forceRefresh`

**Trigger:** User opens AddToPlaylistDialog → stale cache triggers `_backgroundRefreshPlaylist()` → user toggles a song before refresh completes.  
**Location:** `subsonic_service.dart:488-495` vs `add_to_playlist_dialog.dart:79-143`

**Mechanism:**  
1. `getPlaylistSongs(id)` returns stale cached data and fires `_backgroundRefreshPlaylist(id)` (L458).
2. The user sees stale data and decides the song is not in the playlist.
3. User taps to add → `_toggleEntry()` fires `updatePlaylist(playlistId, songIdToAdd: songId)`.
4. `_backgroundRefreshPlaylist()` completes and writes fresh data to SQLite — but nobody consumes it because the provider already emitted.
5. Meanwhile `_toggleEntry()` then calls `ref.invalidate(songsInPlaylistProvider(playlistId))` which triggers a *new* fetch with `forceRefresh: true`.
6. This new fetch can race with the tail end of `_backgroundRefreshPlaylist()` — both call `_cache.putSongs()` for the same playlist ID, and the last writer wins. If the background refresh wrote the old state *after* the toggle's force-refresh, the cache reverts.

**Result:** Checkmark flickers. Song appears added then disappears, or vice versa.

---

### RC-7: `ListeningEventCollector._openEvent` Not Guarded Against Concurrent Access

**Trigger:** Rapid track changes (e.g., holding the skip button).  
**Location:** `listening_event_collector.dart:22-72`

**Mechanism:**  
1. `onSongStarted()` reads `_openEvent` at L31, then sets it to null at L149 inside `_closeEvent()`, then creates a new `PlayEvent` at L51.
2. If `onSongStarted()` is called again before the previous call completes `_writeEvent()` (which is async fire-and-forget), the sequence is:
   - Call A reads `_openEvent` → not null, calls `_closeEvent()` → sets `_openEvent = null` → writes DB (async, not awaited) → creates new event
   - Call B fires before Call A creates new event → reads `_openEvent` as null → skips close → creates new event
   - Call A then writes `_openEvent = newEvent_A`, Call B overwrites with `_openEvent = newEvent_B`
   - `newEvent_A` is never closed, leaked as an orphaned row in the database.

**Result:** Orphaned `PlayEvent` rows with no `ts_end` accumulate in the database, corrupting analytics stats.

---

### RC-8: `RecommendationService._saveData()` Concurrent SharedPreferences Writes

**Trigger:** Two rapid song transitions call `trackSongPlay()` back-to-back.  
**Location:** `recommendation_service.dart:76-129`

**Mechanism:**  
1. `trackSongPlay()` mutates in-memory maps (`_profiles`, `_artistAffinity`, etc.) synchronously (L83-125).
2. Then calls `await _saveData()` which gets `SharedPreferences.getInstance()` and serializes to JSON (L371-389).
3. If a second `trackSongPlay()` fires while the first `_saveData()` is still awaiting the SharedPreferences write, the second call mutates the maps *again* synchronously, then fires its own `_saveData()`.
4. Both `_saveData()` calls race to write to SharedPreferences. The second call's JSON includes both mutations, but the first call's JSON only includes the first mutation.
5. If the first call's `setString()` completes *after* the second call's `setString()`, the second mutation is overwritten and lost.

**Result:** Recommendation data silently lost. Over time, play history drifts from reality, degrading recommendation quality.

---

### RC-9: `player.setAudioSource()` During Active Playback Causes Stream Listener Cascade

**Trigger:** Any shuffle toggle, queue replacement, or autoplay append that calls `_rebuildSource()`.  
**Location:** `audio_handler.dart:193-208` + `player_provider.dart:154-228`

**Mechanism:**  
1. `_rebuildSource()` calls `player.setAudioSource(...)` which internally resets just_audio's state machine.
2. This emits a burst of events: `currentIndex → 0`, `playing → false`, `processingState → idle → buffering → ready`.
3. `PlayerNotifier._init()` listeners react to *every* event:
   - `currentIndexStream` fires with index 0 → updates `state.currentIndex` → pushes wrong song to history → triggers autoplay check
   - `playingStream` fires with `false` → UI flashes pause state
   - `processingStateStream` fires `completed` → may trigger another autoplay fetch
4. The caller then sets the correct index and calls `player.play()`, but the listeners have already fired with stale/wrong values.

**Result:** Ghost history entries, incorrect analytics events, potential double autoplay fetch, momentary UI flicker showing wrong song.

---

### RC-10: `_persistState()` Called from Position Stream Without Debouncing

**Trigger:** Continuous playback — fires every time `position.inSeconds % 5 == 0`.  
**Location:** `player_provider.dart:273-275`

**Mechanism:**  
1. `positionStream` fires at ~1Hz. Every 5 seconds, `_persistState()` is called.
2. `_persistState()` calls `HiveBoxes.session.put(...)` and `HiveBoxes.prefs.put(...)` (L131-142).
3. Hive puts are async under the hood but called without `await` — they queue in Hive's internal write scheduler.
4. If the user triggers `setQueue()` or `toggleShuffle()` while a `_persistState()` write is in the Hive queue, `_loadPersistedState()` (called on next startup) may read a half-written state where `currentTrackId` points to a song from the new queue but `lastPositionMs` still reflects the old song.

**Result:** On cold restart, app seeks to a position that belongs to a different song, causing audio glitch or wrong playback position.

---

### RC-11: Concurrent `updatePlaylist()` Calls With Stale `songIndexToRemove`

**Trigger:** User swipes-to-remove a song from playlist while another user/device also modifies the same playlist.  
**Location:** `add_to_playlist_dialog.dart:149-195` + `subsonic_service.dart:510-528`

**Mechanism:**  
1. `_removeSongFromPlaylist()` fetches fresh songs at L157 and computes `serverIndex` (the positional index of the song in the playlist).
2. Between the fetch and the `updatePlaylist()` call at L165, another modification (from a different thread, dialog, or device) adds/removes a song, shifting indices.
3. `updatePlaylist(playlistId, songIndexToRemove: serverIndex)` sends the *stale* index to the Subsonic server.
4. The server removes the song at the wrong index — the user's intended song stays, a different song is removed.

**Result:** Wrong song deleted from playlist. Data loss — requires manual correction on the server.

---

### RC-12: `playPlaylist()` shuffle+setQueue Race When `await computeShuffle()` Is Slow

**Trigger:** User taps "Shuffle Play" on a large playlist.  
**Location:** `player_provider.dart:346-375`

**Mechanism:**  
1. `playPlaylist(songs, shuffle: true)` sets `_isShuffling = true` (L360).
2. Then `await _audioHandler.computeShuffle(pool, ...)` runs on an isolate (L366-367). For 5000 songs with weighted shuffle, this can take 200-400ms.
3. During this await, the user taps a song tile in the UI (e.g., play a specific song). This calls `setQueue()` which clears history, sets a new queue, and calls `_audioHandler.setQueue()`.
4. `playPlaylist()` resumes, overwrites the queue with the shuffled result, sets `currentIndex: 0`, and calls `_audioHandler.setQueue()` again.
5. The user's explicit song selection is silently replaced by the shuffled queue.

**Result:** User taps song A but hears song B (the first song of the shuffled queue). Extremely confusing.

---

### RC-13: `_fetchAndAppendSimilar()` Snapshots Queue Length Before But Checks Index After

**Trigger:** User skips tracks rapidly while autoplay is fetching similar songs.  
**Location:** `player_provider.dart:651-704`

**Mechanism:**  
1. `_fetchAndAppendSimilar()` snapshots `state.queue.length` at L675 and `state.currentIndex` at L676-677.
2. Then `await _subsonicService.getSimilarSongs(seedSong.id, count: 10)` (L655-656) — network call, 200-2000ms.
3. During the await, user skips forward → `currentIndexStream` fires → `state.currentIndex` increments.
4. After the await, L676 re-reads `state.currentIndex` (via `state.`) which is now *higher* than when the snapshot was taken.
5. `wasAtEnd` computation uses the stale `queueLengthBeforeAppend` but the current `state.currentIndex`, which may be `> queueLengthBeforeAppend - 1` due to the skips.
6. So `wasAtEnd = true` even though the user has navigated away from the end of the queue.
7. This causes `player.seek(Duration.zero, index: nextIndex)` at L693 to *forcibly* jump the user to the first newly-appended song, interrupting whatever they're currently listening to.

**Result:** Playback hijacked — user is listening to a song and suddenly gets teleported to an autoplay song.

---

### RC-14: `songsInPlaylistProvider` autoDispose + Concurrent `_toggleEntry` Invalidation Race

**Trigger:** User rapidly taps add/remove on different playlists in the dialog.  
**Location:** `library_provider.dart:102-109` + `add_to_playlist_dialog.dart:79-143`

**Mechanism:**  
1. `songsInPlaylistProvider` is `autoDispose.family` — it's disposed when no widget watches it.
2. `_toggleEntry()` calls `ref.invalidate(songsInPlaylistProvider(playlistId))` at L114.
3. If the `Consumer` widget for that playlist row is mid-rebuild (e.g., due to a previous invalidation), the invalidation triggers a new provider lifecycle while the old one is being disposed.
4. Riverpod's autoDispose can race: the old provider's `onDispose` callback fires after the new provider has already started fetching, leading to a dangling `Future` that the framework ignores silently.
5. In the pathological case, the disposed provider's stale data is briefly shown before the new provider's data arrives, causing a visual flicker where the checkmark appears and disappears.

**Result:** UI state inconsistency — checkmark flickers between checked/unchecked during rapid toggling.

---

### RC-15: `_loadPersistedState()` Runs After `_init()` — Player Seeks Before Streams Are Ready

**Trigger:** Cold start with a persisted position.  
**Location:** `player_provider.dart:94-108`

**Mechanism:**  
1. Constructor calls `_init()` (L106) which sets up stream listeners.
2. Then `_loadPersistedState()` (L107) calls `player.seek(Duration(milliseconds: lastPosMs))` (L127).
3. `player.seek()` is called on an `AudioPlayer` that has no audio source set yet (the queue is empty at this point).
4. just_audio silently ignores seeks on a player with no source, OR throws depending on the platform implementation.
5. If it throws, the exception is uncaught because `_loadPersistedState()` is sync (no try-catch, no await).

**Result:** Silent failure on startup — persisted position is lost, or unhandled exception crashes the app on certain Android versions.

---

### RC-16: Hive `put()` and `get()` Interleave Across Async Boundaries

**Trigger:** Settings save + concurrent settings read (e.g., player provider reading settings while settings screen saves).  
**Location:** `settings_provider.dart:175-198`, `core/hive_boxes.dart`

**Mechanism:**  
1. `saveSettings()` awaits `auth.put(kServerUrl, url)` at L185.
2. Between L185 and L186 (`auth.put(kUsername, user)`), the player provider reads `settingsProvider` to get credentials for a network call.
3. It reads the *new* serverUrl but the *old* username (the put hasn't completed yet).
4. The SubsonicService is constructed with mismatched credentials → auth failure → network error.

**Result:** Transient authentication failures after saving settings, requiring app restart. Particularly insidious because it's timing-dependent and non-reproducible.

---

### RC-17: `TranscodingService._initConnectivityWatcher()` Double-Init Race

**Trigger:** `setSmartEnabled(true)` called while `_loadFromHive()` is still executing connectivity setup.  
**Location:** `transcoding_service.dart:72-101` vs `140-149`

**Mechanism:**  
1. Constructor calls `_loadFromHive()` (L73) which, if `_smartEnabled` is true, calls `_initConnectivityWatcher()` (L98).
2. `_initConnectivityWatcher()` is async — it `await`s `Connectivity().checkConnectivity()` (L105).
3. Before that await completes, the UI calls `setSmartEnabled(true)` which also calls `_initConnectivityWatcher()` (L144).
4. Now two connectivity listeners are registered (L109-111 in each call). The `_connectivitySub?.cancel()` at L108 only cancels the sub that the *current* invocation has a reference to — the other invocation's sub is orphaned.

**Result:** Duplicate connectivity event handling — `notifyListeners()` fires twice per network change, and one subscription leaks until the service is disposed.

---

### RC-18: `editPlaylist` save + `playlistsProvider` invalidation race with navigation

**Trigger:** User saves playlist edit and navigates back before invalidation completes.  
**Location:** `edit_playlist_screen.dart:54-88`

**Mechanism:**
1. `_save()` calls `service.updatePlaylist(...)` (L62) — network call.
2. Then calls `ref.invalidate(playlistsProvider)` (L73).
3. Then immediately calls `Navigator.pop(context, true)` (L77).
4. The `pop` disposes the `ConsumerState`, but `playlistsProvider` invalidation triggers an async re-fetch.
5. If the parent screen's `Consumer` widget re-renders *before* the playlist re-fetch completes, it shows stale data.
6. More critically, `ref.invalidate()` on a `keepAlive()` provider triggers a new fetch, but the result may arrive after the parent has already built with the old data, and since it's `keepAlive`, there's no `autoDispose` rebuild.

**Result:** Parent screen shows the old playlist name/details until the next full rebuild (e.g., tab switch).

---
