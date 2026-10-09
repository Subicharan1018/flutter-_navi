# Smart Shuffle Queue Implementation Audit & Context Handoff

**File:** `SMART_SHUFFLE_QUEUE_AUDIT_REPORT.md`  
**Date:** September 10, 2026  
**Scope:** Smart Shuffle (`smartLocal`), Queue Management, Next 16 Multi-Batch Refill, "Play Next" (`insertNext`), "Add to Queue" (`addToQueue`), Concurrency & Playback Lifecycle  
**Primary Files Under Investigation:**
- `lib/providers/player_provider.dart`
- `lib/services/navi_audio_handler.dart`
- `lib/features/ai_shuffle/logic/shuffle_providers.dart`
- `lib/features/ai_shuffle/ui/ai_shuffle_screen.dart`
- `test/features/ai_shuffle/smart_shuffle_lifecycle_scenarios_test.dart` (New Comprehensive Test Suite)

---

## 1. Executive Summary

This document records the exact findings, forensic analysis, test implementations, and roadmap for the Smart Shuffle queue system.

### The Question: Good Faith or Half-Baked Code?
- **The verdict**: The Smart Shuffle subsystem was conceived in **good faith with strong architectural intentions** (e.g. 16-song pool windowing to prevent server lag, move-based non-rebuffering ExoPlayer reorders, and Markov transition scoring), **BUT the concurrency, multi-batch refills, and queue mutations were left half-baked**.
- Under normal linear playback of 16 songs, it works. But under real-world usage—such as inserting a track via "Play Next", adding to the tail, or hearing through 3 to 5 consecutive batches (48 to 80+ songs)—**silent race conditions wipe out user-added tracks, desktop playback hitches at track 13, and pool exhaustion blocks autoplay permanently**.

---

## 2. Forensic Analysis: Deep Dive into Discovered Flaws

### Flaw 1: Concurrency Lock Missing in Refill (`_fetchAndReorderSmartLocal`)
- **Location**: `lib/providers/player_provider.dart:2092-2233`
- **The Problem**:
  `insertAllNext`, `addToQueue`, `reorderQueue`, `removeFromQueue`, and `reshuffleActiveQueue` all acquire `_queueOpLock`.
  However, `_fetchAndReorderSmartLocal` **neither awaits nor acquires `_queueOpLock`**.
- **What Happens**:
  1. At song 13 (where `remainingAhead <= 3`), `_fetchAndReorderSmartLocal` begins an asynchronous HTTP fetch to `/next` (takes ~300ms to 1s).
  2. It snapshots `pastAndPresent` and `existingFuture` (e.g., songs 14, 15, 16).
  3. While that HTTP fetch is in flight, the user taps **"Play Next"** on `Song X`.
  4. `insertNext` runs immediately because `_queueOpLock` was free. `Song X` is inserted at index 14.
  5. The HTTP fetch completes. It builds `orderedFuture = [...existingFuture, ...orderedBatch]`. **`existingFuture` does NOT contain `Song X`**.
  6. `commitSmartLocalOrder` overwrites `_currentQueue` with `[...pastAndPresent, ...orderedFuture]`.
  7. **RESULT**: `Song X` is completely erased from both the queue and the UI. Furthermore, because `_playlist` in ExoPlayer had `Song X` inserted, `playlistLen != n` triggers an emergency fallback `_rebuildSource`, jarring the active track.

---

### Flaw 2: Desktop Playback Stoppage on Refill Commit
- **Location**: `lib/services/navi_audio_handler.dart:747-752`
- **The Problem**:
  ```dart
  if (_isLinux) {
    final savedPosition = player.position;
    await _rebuildSource(anchorIndex, initialPosition: savedPosition);
    if (player.playing) player.play();
    return;
  }
  ```
  Note that in `NaviAudioHandler`, `_isLinux` represents **Windows, macOS, and Linux** desktop platforms.
- **What Happens**:
  On desktop, Navi uses a single-track bridge (`_linuxIndex`). Only the active song is loaded in `AudioPlayer`; future songs exist strictly in in-memory `_currentQueue`.
  When `commitSmartLocalOrder` runs at song 13, it calls `_updateQueueAfterAnchor`. Instead of simply updating the in-memory list, it calls `_rebuildSource(anchorIndex)`, which stops the player, reloads the current track from scratch, and seeks.
  **RESULT**: On Windows and Linux, the user experiences an audible 1-2 second stutter/buffering pause at track 13 of every session.

---

### Flaw 3: Autoplay Permanently Blocked on Pool Depletion
- **Location**: `lib/providers/player_provider.dart:694-719`
- **The Problem**:
  ```dart
  final isSmartLocal = settings.shuffleAlgorithm == ShuffleAlgorithm.smartLocal && state.shuffleMode;

  if (state.queue.isNotEmpty) {
    final remainingAhead = state.queue.length - 1 - index;
    if (isSmartLocal && remainingAhead <= _smartLocalRefillThreshold) {
      if (_playlistPool.isNotEmpty && transitionType != 'user_selected') {
        _triggerSmartLocalFetchIfNeeded();
      }
    } else if (state.autoplayMode && !isSmartLocal) {
      // Autoplay triggers here
    }
  }
  ```
- **What Happens**:
  When hearing through a playlist until `_playlistPool` is exhausted (0 songs left):
  `isSmartLocal` remains `true`.
  Because `if (isSmartLocal ...)` is matched, the `else if (state.autoplayMode && !isSmartLocal)` **can never execute**.
  **RESULT**: When the last song of a smart shuffle playlist finishes, music stops permanently even if the user has Autoplay turned ON.

---

### Flaw 4: `_lastKnownIndex` Desync in `reshuffleActiveQueue`
- **Location**: `lib/providers/player_provider.dart:1968-1974`
- **The Problem**:
  `reshuffleActiveQueue` keeps the active song and puts it at index 0 of `newQueue`.
  `state = state.copyWith(queue: newQueue, currentIndex: 0);`
  However, it **forgets to update `_lastKnownIndex = 0` and `_trackedIndexForCompletion = 0`**.
- **What Happens**:
  If the user was at track 5 before reshuffling, `_lastKnownIndex` remains 5. When track 0 finishes, `prevIndex` is evaluated as 5, so track 5 from the new queue is recorded as having played instead of track 0!

---

### Flaw 5: Mid-Session Shuffle Toggle Bypasses 16-Song Pool Architecture
- **Location**: `lib/providers/player_provider.dart:1645-1715`
- **The Problem**:
  If a user starts a 100-song playlist in regular (unshuffled) order, all 100 songs are loaded into `state.queue`.
  If the user taps the Shuffle button at song 5, `_applySmartLocalAlgorithm` takes `future = queue.sublist(6)` (94 songs) and sends **all 94 songs as `candidates` to the server** in one giant HTTP request.
  It does not split them into `_playlistPool` or window them in batches of 16.

---

## 3. Playback Lifecycle Traces

### Trace A: "Play Next" (`insertNext`) Lifecycle
1. User starts Smart Shuffle on a 50-song playlist.
2. Initial queue: `[S0 (playing), S1, S2, ... S16]` (17 songs). `_playlistPool` has 33 songs.
3. User taps "Play Next" on `Song X`.
4. `insertNext` atomically inserts `Song X` at `currentIndex + 1 = 1`.
5. Queue becomes: `[S0 (playing), Song X, S1, S2, ... S16]` (18 songs).
6. S0 finishes naturally -> Feedback sent for S0 -> Player moves to index 1 (`Song X`).
7. `Song X` finishes naturally -> Feedback sent for `Song X` (`endReason: 'natural'`) -> Player moves to index 2 (`S1`).
8. Smart shuffle sequence continues unbroken.

### Trace B: "Add to Queue" (`addToQueue`) Lifecycle & Next 16 Refill
1. Queue has 17 songs: `[S0 (playing), ... S16]`.
2. User taps "Add to Queue" on `Song Y`.
3. `Song Y` is appended to the tail at index 17: `[S0, ... S16, Song Y]`.
4. Playback advances to song 14 (`remainingAhead = 18 - 1 - 14 = 3`).
5. Refill triggers:
   - `existingFuture` = `[S15, S16, Song Y]`.
   - `seedForBatch` = `existingFuture.last = Song Y`.
   - Next 16 songs (S17..S32) are taken from `_playlistPool`.
   - Server orders S17..S32 seeded by `Song Y`.
   - Queue becomes: `[S0..S14, S15, S16, Song Y, S17..S32]` (34 songs).
   - `Song Y` is preserved and plays before the new smart batch!

### Trace C: 3 to 5 Multi-Session Marathon (70-80 Songs)
- **Session 1 (Songs 0-16)**: Initial 17 songs play. At song 13/14, Refill 1 fires. Pool drops from 63 to 47. Queue expands to 33.
- **Session 2 (Songs 17-32)**: At song 29/30, Refill 2 fires. Pool drops from 47 to 31. Queue expands to 49.
- **Session 3 (Songs 33-48)**: At song 45/46, Refill 3 fires. Pool drops from 31 to 15. Queue exceeds 50 songs -> **`_prunePlayedSongs()` triggers**, safely pruning the first 15 played tracks while shifting `currentIndex` down by 15.
- **Session 4 (Songs 49-64)**: At song 61/62, Refill 4 fires. Remaining 15 songs in pool are appended. Pool drops to 0 (exhausted).
- **Session 5 (Pool Exhausted)**: Songs 65-80 play out. When the final song completes, Autoplay smoothly takes over (with Fix 3 applied).

---

## 4. What Was Built in This Session

We created the exhaustive test suite:  
**`test/features/ai_shuffle/smart_shuffle_lifecycle_scenarios_test.dart`**

It contains dedicated, deterministic test scenarios using mocked `ShuffleRepository`, `AudioPlayer`, and `NaviAudioHandler`:
1. **Scenario 1**: Initial Playback with 16-song batch from large playlist (seed + 16 pool songs = 17).
2. **Scenario 2**: "Play Next" (`insertNext`) during active Smart Shuffle and subsequent completion handoff.
3. **Scenario 3**: Consecutive "Play Next" calls stacking in proper reverse order (`[Current, B, A, ...]`).
4. **Scenario 4**: "Add to Queue" (`addToQueue`) appending to tail and preserving position.
5. **Scenario 5**: Multi-Session Marathon hearing through 4 consecutive batches of 16 songs (70-song playlist).
6. **Scenario 6**: User jump near the end (`transitionType == 'user_selected'`) preventing premature refills.
7. **Scenario 7**: Server 500 error during refill cleanly falling back to raw pool order without dropping tracks.
8. **Scenario 8**: Active queue reshuffle (`reshuffleActiveQueue`) preserving the playing track and replacing upcoming tracks.
9. **Scenario 9**: Up Next reordering (`reorderQueue`) and song removal (`removeFromQueue`).

---

## 5. Next Steps for Resuming

When ready to continue, follow these exact steps:

1. **Run the test suite**:
   ```bash
   flutter test test/features/ai_shuffle/smart_shuffle_lifecycle_scenarios_test.dart
   ```
2. **Apply the 4 targeted fixes in `lib/providers/player_provider.dart`**:
   - **Fix 1**: In `_fetchAndReorderSmartLocal`, await `_queueOpLock?.future`, and when committing, re-read live `_audioHandler.currentQueue` so any concurrent `insertNext` / `addToQueue` items are merged rather than overwritten.
   - **Fix 2**: In `lib/services/navi_audio_handler.dart:747`, if `_isLinux` is true and `anchorIndex == _linuxIndex`, only update `_currentQueue` in memory and skip `_rebuildSource()`.
   - **Fix 3**: In `lib/providers/player_provider.dart:700`, if `isSmartLocal && _playlistPool.isEmpty && state.autoplayMode`, call `_triggerAutoplayIfNeeded()`.
   - **Fix 4**: In `reshuffleActiveQueue`, set `_lastKnownIndex = 0` and `_trackedIndexForCompletion = 0`.
3. **Re-verify all tests**:
   Ensure all 9 scenarios in `smart_shuffle_lifecycle_scenarios_test.dart` and `test/shuffle_test.dart` pass 100%.
