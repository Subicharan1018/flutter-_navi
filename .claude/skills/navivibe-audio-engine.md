---
name: navivibe-audio-engine
description: >
  Use this skill whenever touching audio playback, queue management, shuffle,
  gapless playback, background audio, scrobbling, or listening telemetry in
  NaviVibe. Triggers include: modifying AudioHandler, PlayerProvider, shuffle
  algorithms, ListeningEventCollector, ListeningLogService, ScrobbleService,
  or any file in Community 61. This skill enforces the strict service boundaries
  of the audio engine — the most tightly coupled cluster in the codebase.
---

# NaviVibe Audio Engine Skill

## Community 61 — The Core Cluster
The 6 most tightly coupled services in NaviVibe:

```
AudioHandler ←→ PlayerProvider
     ↕                ↕
OfflineService    ListeningEventCollector
     ↕                ↕
SubsonicService ←→ Advanced Shuffle Algorithms
```

**Rule: Never bypass this cluster. Every audio operation flows through it.**

## AudioHandler Rules

### Queue Management
- Always use `ConcatenatingAudioSource.move()` for reordering — never naive reassignment
- This is `Gapless Incremental Reordering` — an inferred architectural pattern
- Replacing with naive queue reassignment causes audible gaps between tracks

```dart
// CORRECT — gapless reorder
await _player.sequence?.move(oldIndex, newIndex); // ✅

// WRONG — naive reassignment causes gaps
_queue = [...newOrder]; // ❌ breaks gapless playback
```

### Background Playback
- `AudioHandler` extends `BaseAudioHandler` from `just_audio_background`
- Lock screen controls are managed here — do not add UI logic to this class
- Platform channels for Linux are in Community 28 (`my_application.cc`, `fl_register_plugins`)

## PlayerProvider Rules
- The ONLY entry point for playback state from UI layer
- 40 edges — changes ripple to 40 dependents
- Always calls `ListeningEventCollector` on play events — do NOT remove this
- Use `ref.read(playerProvider.notifier)` from UI callbacks only

## ListeningEventCollector Rules
- Bridges 11 communities (betweenness 0.076)
- Semantically similar to `ListeningLogService` — keep their logic in sync
- Currently defines test utilities (`pumpMicrotasks`, `makeSong`, `generateUuid`) — do not move these without updating test Communities 13, 18, 20, 34, 35, 43, 44, 49
- Feeds data to `ScrobbleService` and `ListeningLogService`

## Shuffle Algorithm Rules
- Heavy computation runs in isolates — never on main thread
- `applyShuffleAlgorithm` is in Community 13 (god node territory)
- Smart local algorithm: `_applySmartLocalAlgorithm`
- Interleaving logic: `_interleave` in Community 22
- `commitSmartLocalOrder` finalizes the queue after shuffle

## Scrobbling Rules
- `ScrobbleService` is in Community 73 with `ListeningEventCollector` and `ListeningLogService`
- All three must stay in sync — they handle overlapping telemetry responsibilities
- Requires connectivity check before submitting (`package:connectivity_plus`)
- Failed logs are queued via `_queueFailedLog` and retried

## Offline Playback Rules
- `OfflineService` manages downloads via `DownloadStateNotifier`
- Download state flows: `statusOf`, `progressOf`, `_set`, `_setFailed`
- Offline data hyperedge: `offline_service` ↔ `app_database` ↔ `playlist_cache_table`
- Never bypass `OfflineService` for file access — it owns the cache path logic

## SubsonicService Rules
- 46 edges, bridges 11 communities (betweenness 0.077)
- The ONLY class allowed to make HTTP calls to the Navidrome/Subsonic server
- Auth is handled here — never store raw credentials outside `HiveBoxes`
- WebDAV upload URI built via `_buildWebDavUploadUri` — do not duplicate this logic
- All URL building goes through `_buildUrl` and `_buildStableUrl`

## After Any Audio Change
```bash
flutter test test/audio_handler_test.dart
flutter test test/shuffle_test.dart
flutter analyze
```

Check that `ListeningEventCollector` still connects to both `PlayerProvider` and `ScrobbleService` after changes.
