# Task: Fix Shuffle Lag, Timer Bugs & Performance Issues

## Pre-flight checks
- [x] OfflineService singleton confirmed (factory constructor → `_instance`)
- [x] BUG 2 gapless race fix scoped
- [x] BUG 6 Dart LinkedHashMap insert-order caveat noted

## palette_cache.dart
- [x] Full rewrite to LRU cache (50 entries, LinkedHashMap + remove/reinsert)
- [x] Add `getColorsFor()` with clarifying LRU comment
- [x] Maintain backward-compatible `colors`/`songId` getters

## audio_handler.dart
- [x] Add `_precomputeOfflinePaths()` helper (batches File.existsSync calls)
- [x] Add `_toSourceWithPaths()` helper (uses pre-computed map)
- [x] Fix comment: "Hive lookups" → "File.existsSync() calls" in both call sites
- [x] `_rebuildSource()` already used the helpers (pre-existing from last session)
- [x] `_updateQueueAfterAnchor()` already used the helpers (pre-existing from last session)

## player_provider.dart (BUG 1 — timer)
- [x] `_trackChangeTimer` callback wired to `_collector.onSongStarted()` (confirmed in file)

## player_provider.dart (BUG 2 — scrobble)
- [x] Fields declared: `_scrobbleListenDuration`, `_scrobblePlayStart`
- [x] `_scrobbleThreshold` corrected to pure 50% (`trackDuration * 0.5` only, no min())
- [x] `_scrobbleListenDuration` reset on song change
- [x] Gapless fix: `_scrobblePlayStart` set via `player.playing` (not `state.isPlaying`)
- [x] `playingStream` listener uses `_scrobblePlayStart != null` as old-state guard
- [x] Dual-threshold check in `positionStream`: position >= 50% OR listened >= 4min
- [x] `stop()` resets `_scrobbleListenDuration` and `_scrobblePlayStart`

## player_provider.dart (BUG 4 — stale currentIndex)
- [x] `applyShuffleAlgorithm()` reads `player.currentIndex` AFTER shuffle (confirmed in file)

## player_provider.dart (BUG 5 — persist dedup)
- [x] `_lastPersistSecond` field declared
- [x] Position stream guard: `sec != _lastPersistSecond` before calling `_persistState()`
- [x] `_lastPersistSecond` reset on song change (via `_scrobbleListenDuration = Duration.zero` block)
