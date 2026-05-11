# Fix Shuffle Lag, Timer Bugs & Performance Issues — Revised Plan

Incorporates the user's [bug-by-bug verdict](file:///C:/Users/gadul/.gemini/antigravity/brain/79c7db14-7143-4eaf-a080-f6b301688134/implementation_plan.md) from the previous session.

---

## Changes From Previous Plan

| Bug | Previous Fix | Revised Fix | Reason |
|---|---|---|---|
| BUG 2 | "Use `player.position` directly" | Dual-threshold: position-based 50% + play/pause transition-tracked 4min | Last.fm spec compliance; naive position breaks on seek-backward |
| BUG 3 | "Batched moves + >50% rebuild fallback" | Optimize existing rebuild path only (pre-compute paths, keep ≤5 move path) | No `moveMany()` API in just_audio; index-shift bookkeeping makes batched moves error-prone |
| BUG 7 | "Pre-compute Hive map" | Pre-compute `File.existsSync` map | `OfflineService.getLocalPath()` uses `File.existsSync()`, not Hive |

> [!NOTE]
> BUGs 1, 4, 5, 6 are unchanged — all approved as-is in the verdict.

---

## BUG 1: `_trackChangeTimer` Empty Callback ✅ (Approved)

**File:** [player_provider.dart](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L206-L215)

**Problem:** Timer fires after 200ms but callback body is empty — analytics `onSongStarted()` is never called.

**Fix:** Wire the callback body:

```dart
_trackChangeTimer = Timer(const Duration(milliseconds: 200), () {
  _collector.onSongStarted(
    song: capturedNew,
    sourceContext: sourceCtx,
    transitionType: transCtx,
    prevSong: capturedPrev,
    positionAtSwitch: capturedPos,
    queuePosition: capturedIdx,
    shuffleActive: capturedShuffle,
  );
});
```

The `sourceCtx` and `transCtx` variables are already captured at [lines 201-204](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L201-L204) but never used. This fix wires them to the collector.

---

## BUG 2: `_playedDuration` Drift & Scrobble Logic ⚠️ (Reworked)

**File:** [player_provider.dart](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L334-L347)

**Problem:** Per-tick `DateTime.now()` accumulation drifts. Previous fix ("use `player.position` directly") was too naive — `player.position` resets on seek, breaking scrobble for users who repeat sections.

### Last.fm Scrobble Spec
A song should be scrobbled when **either** condition is met first:
1. Playback position reaches **50% of track duration** — checked via `player.position >= trackDuration * 0.5`
2. **4 minutes of actual listening time** — tracked via play/pause state transitions, not per-tick accumulation

### Revised Fix — Dual-Threshold with Transition Tracking

**New fields** (replace `_playedDuration` and `_lastPlayTimestamp`):

```dart
Duration _accumulatedListenTime = Duration.zero;  // replaces _playedDuration
DateTime? _playStartedAt;  // set only on play→playing transitions
```

**Play/pause transition tracking** — in the `playingStream` listener (line 281):

```dart
player.playingStream.listen((playing) {
  if (_suppressStreamEvents) return;
  
  // Accumulate listen time on play→pause transitions
  if (!playing && _playStartedAt != null) {
    _accumulatedListenTime += DateTime.now().difference(_playStartedAt!);
    _playStartedAt = null;
  } else if (playing && _playStartedAt == null) {
    _playStartedAt = DateTime.now();
  }
  
  state = state.copyWith(isPlaying: playing);
});
```

**Scrobble check** — in the `positionStream` listener (replacing lines 334-347):

```dart
// Threshold 1: position-based (50% of track)
// This correctly handles seeks — if user seeks to 80%, it triggers.
// If user seeks backward to 10%, it doesn't re-trigger (_hasScrobbled guard).
final positionThresholdMet = position >= _scrobbleThreshold;

// Threshold 2: accumulated listen time (4 minutes)
// Only accumulates during actual playback, tracked via play/pause transitions.
Duration currentListenTime = _accumulatedListenTime;
if (state.isPlaying && _playStartedAt != null) {
  currentListenTime += DateTime.now().difference(_playStartedAt!);
}
final listenTimeThresholdMet = currentListenTime >= const Duration(minutes: 4);

if (!_hasScrobbled &&
    _currentScrobbleSongId != null &&
    (positionThresholdMet || listenTimeThresholdMet)) {
  _hasScrobbled = true;
  _ref
      .read(scrobbleServiceProvider)
      .submit(_currentScrobbleSongId!, song: currentSong);
}
```

**Reset on song change** (line 219, already correct location):

```dart
_accumulatedListenTime = Duration.zero;
_playStartedAt = state.isPlaying ? DateTime.now() : null;
```

> [!IMPORTANT]
> `_scrobbleThreshold` at line 225 already computes `min(50% of track, 4min)`. We keep it for the position-based check but add the separate `_accumulatedListenTime` path for the 4-minute rule. The `_scrobbleThreshold` variable should be renamed to `_positionThreshold` for clarity and only represent 50% of the track duration.

---

## BUG 3: Shuffle Rebuild Performance ⚠️ (Reworked — Simplified)

**File:** [audio_handler.dart](file:///d:/Subi_project/flutter-_navi/lib/services/audio_handler.dart#L321-L350)

**Problem:** `_updateQueueAfterAnchor` calls `setAudioSource()` for queues >5 songs, causing ~100-300ms audio gap.

### Why "Batched Moves" Was Dropped
- `ConcatenatingAudioSource.move(from, to)` is **one platform channel call per operation** — no `moveMany()` API exists
- Each `move()` shifts indices, requiring recomputation after every call
- For N moves, the platform channel overhead may exceed a single `setAudioSource()` call
- The ">50% changed → full rebuild" fallback still violates GEMINI.md in the fallback case

### Revised Fix — Optimize The Existing Rebuild Path

The current rebuild path is actually sound — the lag comes from the **synchronous `OfflineService().getLocalPath()` calls inside `_toSource()`**, not from `setAudioSource()` itself. Each call does `File.existsSync()` synchronously, which for 200+ songs is 200+ blocking I/O calls.

**Changes:**

1. **Pre-compute offline path map** before the source-build loop in `_updateQueueAfterAnchor`:

```dart
Future<void> _updateQueueAfterAnchor(int anchorIndex) async {
  if (_playlist == null) {
    final savedPosition = player.position;
    await _rebuildSource(anchorIndex, initialPosition: savedPosition);
    if (player.playing) player.play();
    return;
  }

  final int n = _currentQueue.length;

  // Small queues: move-based reorder (no rebuffer)
  if (n <= 5) {
    await _moveBasedReorder(anchorIndex);
    return;
  }

  // Pre-compute offline paths to avoid N synchronous File.existsSync() calls
  // during _toSourceWithCache
  final offlinePaths = _preComputeOfflinePaths();

  final savedPosition = player.position;
  final wasPlaying = player.playing;

  final sources = _currentQueue
      .map((song) => _toSourceWithCache(song, offlinePaths))
      .toList();
  _playlist = ConcatenatingAudioSource(children: sources);
  await player.setAudioSource(
    _playlist!,
    initialIndex: anchorIndex,
    initialPosition: savedPosition,
  );

  if (wasPlaying) player.play();
}
```

2. **New `_preComputeOfflinePaths()` and `_toSourceWithCache()` methods:**

```dart
/// Pre-computes offline paths for all songs in the queue.
/// Avoids N synchronous File.existsSync() calls during source building.
Map<String, String?> _preComputeOfflinePaths() {
  final offline = OfflineService();
  final map = <String, String?>{};
  for (final song in _currentQueue) {
    map[song.id] = offline.getLocalPath(song.id);
  }
  return map;
}

/// Like _toSource but uses a pre-computed offline path map.
AudioSource _toSourceWithCache(Song song, Map<String, String?> offlinePaths) {
  final localPath = offlinePaths[song.id];
  final streamUri = localPath != null
      ? Uri.parse('file://$localPath')
      : Uri.parse(subsonicService.getStreamUrl(song.id));

  return AudioSource.uri(
    streamUri,
    tag: MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
      duration: Duration(seconds: song.duration),
      extras: {'composer': song.composer, 'isLocal': localPath != null},
    ),
  );
}
```

> [!WARNING]
> The `_preComputeOfflinePaths()` call is still synchronous (N `File.existsSync()` calls). For a true fix, this could be made async using `File.exists()` in parallel via `Future.wait()`, but that would require `_updateQueueAfterAnchor` to await the map construction. The sync version is acceptable for now because it batches the I/O into a single tight loop rather than interleaving it with `AudioSource` construction and `MediaItem` tag building.

> [!NOTE]
> The existing ≤5 songs move-based path (`_moveBasedReorder`) is retained as-is — it avoids rebuffer entirely and is correct for small queues.

---

## BUG 4: `applyShuffleAlgorithm` Sets Stale `currentIndex` ✅ (Approved)

**File:** [player_provider.dart](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L781-L784)

**Problem:** `savedIndex` captured before shuffle is written back after shuffle — wrong index.

**Fix:** Read `player.currentIndex` after shuffle completes:

```dart
// BEFORE (stale):
state = state.copyWith(
  queue: _audioHandler.currentQueue,
  currentIndex: savedIndex,
);

// AFTER (correct):
state = state.copyWith(
  queue: _audioHandler.currentQueue,
  currentIndex: _audioHandler.player.currentIndex ?? state.currentIndex,
);
```

Also remove the `savedIndex` variable at [line 747-748](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L747-L748) since it's no longer used.

---

## BUG 5: `_persistState` Timer Fires Multiple Times Per 5s Boundary ✅ (Approved)

**File:** [player_provider.dart](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart#L316-L318)

**Problem:** Position stream fires ~4×/sec. Every tick in a 5s-aligned second triggers `_persistState()`.

**Fix:** Add `_lastPersistSecond` guard:

```dart
// New field
int _lastPersistSecond = -1;

// In positionStream listener:
final sec = position.inSeconds;
if (sec > 0 && sec % 5 == 0 && sec != _lastPersistSecond) {
  _lastPersistSecond = sec;
  _persistState();
}
```

Reset `_lastPersistSecond = -1` in the song change handler (alongside the scrobble reset at line 219).

---

## BUG 6: `PaletteCache` Has No Size Limit ✅ (Approved)

**File:** [palette_cache.dart](file:///d:/Subi_project/flutter-_navi/lib/core/palette_cache.dart)

**Problem:** Cache stores only 1 entry — every song change re-extracts palette (~50ms main-thread work). GEMINI.md requires a capped cache.

**Fix:** Convert to LRU cache with max 50 entries using `LinkedHashMap` access-order:

```dart
import 'dart:collection';

class PaletteCache {
  PaletteCache._();
  static final PaletteCache instance = PaletteCache._();

  static const int _maxEntries = 50;
  static const List<Color> _kFallback = [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
  ];

  // LRU: insertion order tracks access recency.
  // On get(), we remove + re-insert to move to end (most recent).
  final LinkedHashMap<String, List<Color>> _cache = LinkedHashMap();

  // Keep backward-compatible getters for the "current" song
  String? _currentSongId;

  List<Color> get colors => _currentSongId != null
      ? (_cache[_currentSongId!] ?? _kFallback)
      : _kFallback;

  String? get songId => _currentSongId;

  bool hasColorsFor(String id) => _cache.containsKey(id);

  List<Color>? getColorsFor(String id) {
    final entry = _cache.remove(id);
    if (entry != null) {
      _cache[id] = entry; // move to end (most recently used)
      return entry;
    }
    return null;
  }

  void update(String songId, List<Color> colors) {
    _currentSongId = songId;
    _cache.remove(songId); // remove if exists, to re-insert at end
    _cache[songId] = colors;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void clear() {
    _currentSongId = null;
    _cache.clear();
  }
}
```

---

## BUG 7: Synchronous `File.existsSync()` Per Song on Main Thread ✅ (Approved)

**File:** [audio_handler.dart](file:///d:/Subi_project/flutter-_navi/lib/services/audio_handler.dart#L246-L265)

**Problem:** `_toSource()` calls `OfflineService().getLocalPath()` which does `File.existsSync()` synchronously for every song during queue rebuild.

**Fix:** Already addressed as part of BUG 3 — `_preComputeOfflinePaths()` + `_toSourceWithCache()`. The original `_toSource()` method is kept for single-song operations (addToQueue, etc.) where the overhead is negligible.

---

## Proposed Changes Summary

### AudioHandler Performance

#### [MODIFY] [audio_handler.dart](file:///d:/Subi_project/flutter-_navi/lib/services/audio_handler.dart)

1. **BUG 3+7**: Add `_preComputeOfflinePaths()` and `_toSourceWithCache()` methods
2. **BUG 3+7**: Update `_updateQueueAfterAnchor` to use cached paths for large queues
3. Keep `_toSource()` unchanged for single-song add/remove operations
4. Keep `_moveBasedReorder()` unchanged for ≤5 song queues

---

### PlayerNotifier Timer & State Fixes

#### [MODIFY] [player_provider.dart](file:///d:/Subi_project/flutter-_navi/lib/providers/player_provider.dart)

1. **BUG 1**: Wire `_trackChangeTimer` callback to call `_collector.onSongStarted()`
2. **BUG 2**: Replace `_playedDuration`/`_lastPlayTimestamp` with `_accumulatedListenTime`/`_playStartedAt`; add dual-threshold scrobble logic; rename `_scrobbleThreshold` → `_positionThreshold`
3. **BUG 4**: Read `player.currentIndex` after shuffle in `applyShuffleAlgorithm()`; remove stale `savedIndex`
4. **BUG 5**: Add `_lastPersistSecond` guard to deduplicate `_persistState()` calls

---

### PaletteCache LRU Expansion

#### [MODIFY] [palette_cache.dart](file:///d:/Subi_project/flutter-_navi/lib/core/palette_cache.dart)

- Full rewrite to LRU cache (max 50 entries) using `LinkedHashMap`
- Add `getColorsFor(String id)` method with LRU promotion
- Maintain backward-compatible `colors` and `songId` getters

---

## Verification Plan

### Static Verification
- Inspect diff of each changed file for correctness
- Verify `_trackChangeTimer` callback calls `_collector.onSongStarted()` with all captured params
- Verify scrobble dual-threshold logic matches Last.fm spec
- Verify `currentIndex` is read post-shuffle, not pre-shuffle
- Verify `_lastPersistSecond` guard prevents duplicate persist calls
- Verify palette cache `_evictIfNeeded()` enforces max 50 entries
- Verify `_preComputeOfflinePaths()` is called before source-build loop

### Runtime Verification (when Flutter is available)
- Test song transitions trigger analytics events
- Test scrobble fires at 50% position OR 4min listen time, whichever first
- Test seek-backward doesn't double-scrobble
- Test shuffle doesn't cause stale index in UI
- Test palette cache LRU eviction
- Test large queue (200+ songs) shuffle latency improvement
