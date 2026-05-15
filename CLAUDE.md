# CLAUDE.md

This file provides guidance to any AI coding assistant (Claude Code, Gemini CLI, GPT) when working with code in this repository. It incorporates deep insights from the `graphify` knowledge graph. Read this to understand the true architecture and rules before making any changes.

## 1. Project Identity
- **App Name:** NaviVibe
- **Purpose:** A high-performance, aesthetically pleasing music player built for Subsonic-compatible servers.
- **Tech Stack:** Flutter, Riverpod (State Management), just_audio (Audio Engine), Drift (SQLite Database), Hive (Key-Value Store), custom Fragment Shaders.
- **Entry Point:** `lib/main.dart`
- **Platform Targets:** Android, Linux.

## 2. Development Commands
- **Install dependencies**
  ```bash
  flutter pub get
  ```
- **Generate code (freezed, Riverpod, etc.)**
  ```bash
  flutter pub run build_runner build --delete-conflicting-outputs
  ```
- **Run the app locally**
  ```bash
  flutter run
  ```
- **Run all tests**
  ```bash
  flutter test
  ```
- **Run a single test file**
  ```bash
  flutter test path/to/test_file.dart
  ```
- **Run a single test case** (using `-t` pattern)
  ```bash
  flutter test path/to/test_file.dart -t "description of test"
  ```
- **Static analysis & lint**
  ```bash
  flutter analyze
  ```
- **Build production APK** (or app bundle)
  ```bash
  flutter build apk --release
  # or
  flutter build appbundle --release
  ```

## 3. Architecture Overview
NaviVibe uses a **Layered Clean Architecture** combined with **Riverpod 2.0**:
- **Presentation Layer (`lib/screens/`, `lib/widgets/`)**: Functional pages and atomic components. Subscribes to state. **Rule:** Use `ref.watch()` inside `build()` to react to state changes. Never use `ref.read()` in `build()`.
- **State Management Layer (`lib/providers/`)**: Business logic and Notifiers (`PlayerProvider`, `LibraryProvider`, `SettingsProvider`). **Rule:** Use `ref.read()` inside event handlers and callbacks.
- **Service Layer (`lib/services/`)**: Orchestrates data and hardware (`AudioHandler`, `SubsonicService`, `OfflineService`). Uses isolates for heavy tasks.
- **Data Layer (`lib/database/`, `lib/models/`)**: Drift for relational data and Hive for fast key-value storage. Models are immutable (use `copyWith`).

## 4. God Nodes (Current — May 2026)
The `graphify` analysis identified the following as God Nodes. Changes here ripple across the entire app. Run a graph impact check before touching any of these.

1. **`replay_screen.dart` (52 edges):** UI orchestrator for replay statistics. **Refactor Plan:** Extract `_DailyListeningChart`, `_StatsCard`, `_ReplaySongRow`, `_ReplayHeader` into `lib/screens/replay/widgets/`.
2. **`playlist_details_screen.dart` (52 edges):** Manages playlist interactions. **Refactor Plan:** Extract `_ExpandedHeader`, `_LoadingHeader`, `_DownloadAllButton`, `_AddSongsRow`, `_SongListSkeleton` into `lib/screens/playlist/widgets/`.
3. **`package:flutter_riverpod/flutter_riverpod.dart` (49 edges):** Foundational state framework. Bridges 27+ communities.
4. **`package:flutter/material.dart` (43 edges):** Foundational UI framework.
5. **`listening_stats_screen.dart` (43 edges):** Analytics UI. Connected to telemetry, data, and provider layers.
6. **`subsonic_service.dart` (42 edges):** Network boundary. Bridges 11 communities. Never bypass for API calls.
7. **`settings_screen.dart` (40 edges):** Global config UI. Careless edits break app-wide configuration.
8. **`build` (38 edges):** Generic build method — high betweenness due to widget tree frequency.
9. **`mini_player.dart` (37 edges):** Omnipresent UI. Coupled to `PlayerProvider` and routing. Contains swipe gesture for song switching.
10. **`settings_provider.dart` (31 edges):** Central config store. Changes affect almost all UI and service layers.

**Rule for God Nodes:** Before changing any god node, run:
```
/graphify query "what would break if I change X?"
/graphify explain "X"
```
Never add domain-specific feature bloat to these files.

## 5. Service Boundaries (Core Cluster)
The 6 most tightly coupled and critical services:
- **`AudioHandler`**: Background playback, lock-screen/notification controls, gapless queue. Android notification shows: Shuffle, Previous, Play/Pause, Next, Repeat.
- **`OfflineService`**: File caching and offline playback. Filters song list when offline.
- **`PlayerProvider`**: Reactive UI bridge to `AudioHandler`. Entry point for all playback state from UI.
- **`SubsonicService`**: Strict boundary for all remote network calls. 42 edges, 11 communities.
- **`Advanced Shuffle Algorithms`**: Isolate-based background sorting. Fix applied: currentIndex captured AFTER shuffle not before.
- **`ListeningEventCollector`**: Telemetry and scrobble validation. Bridges 11 communities.

**Rules:**
- Never bypass `SubsonicService` for any API requests.
- Never bypass `AudioHandler` for playback queue operations.
- `OfflineService` owns all file path logic — never compute paths elsewhere.
- Changes to `OfflineService` must be reflected in `AudioHandler` queue building.

## 6. Fragile Communities (Do Not Expand)
Communities with cohesion below 0.1. Adding features here worsens the already weak internal cohesion. Extract to new focused modules instead.

| Community | Cohesion | Contents | Rule |
|---|---|---|---|
| Community 0 | 0.07 | Base UI + download flows | Extract to feature slice |
| Community 1 | 0.03 | Now Playing & Queue UI (59 nodes) | Split — highest priority |
| Community 2 | 0.07 | AI Shuffle data + palette cache | Do not expand |
| Community 3 | 0.08 | App exceptions + SubsonicService | Do not expand |
| Community 4 | 0.07 | AI shuffle stats responses | Do not expand |
| Community 5 | 0.08 | CLAUDE.md context nodes | Ignore — doc nodes |
| Community 9 | 0.11 | Drift DB tables + replay queries | Do not expand |
| Community 10 | 0.09 | Shuffle algorithm core | Do not expand |

**Community 1 is the most critical split target** — 59 nodes, cohesion 0.03, contains Now Playing UI mixed with unrelated components.

## 7. Theme System
Confirmed EXTRACTED chain:
`PaletteCache` → `Multi-Engine Theme System` → `FluidBackground Shader`

- `FluidShaderLoader`, `_FluidPainter`, `FluidBackground`, `_FluidBackgroundState` are all confirmed wired in Community 27 (cohesion 0.15).
- `FluidBackground` is used in `now_playing_screen.dart` — confirmed via graph.
- Changing theme rules directly impacts GPU shader inputs.
- Never hardcode colors — use `ThemeTokens`.
- Progress bar in `now_playing_screen.dart` uses `SliderTheme` matching mini player style — do NOT replace with custom painters.

## 8. Isolated Nodes
Current count: **689 isolated nodes** (nodes with ≤1 connection).

Named isolated nodes include: `_SoundBar`, `_SoundBarState`, `_BottomAction`, `_AudioQualityStrip`, `_QualityPill` — these are Now Playing screen widgets recently added but not fully connected.

**Buckets:**
- **BUCKET 1 — Intentionally Isolated (platform boilerplate):** Android Gradle files, Linux ephemeral headers, launcher icons, asset images. Leave alone.
- **BUCKET 2 — Missing Wires (active but undetected):** `PaletteCache`, `AppRouteTransitions`, `Album`, `ListeningStats`, `AppConstants`. AST misses singleton calls and `fromJson` factories. Verify with grep, not graph.
- **BUCKET 3 — Test Utilities:** Zero isolated test utilities. `makeSong` and `pumpMicrotasks` are now in `test/helpers/test_utils.dart`.
- **BUCKET 4 — Dead Code:** Legacy `ic_launcher.png` variants (superseded by `launcher_icon.png`), `my_application.h` (verify CMakeLists.txt).

**Rule:** Before adding any new file, run `/graphify query` to check it won't become isolated. Do not add more isolated nodes to the Now Playing screen — wire them properly.

## 9. Safe Change Rules
Every AI agent must follow these rules before making any change:

1. **Run graph queries first** — never touch a file without querying the graph.
2. **God nodes need impact checks** — list all communities a god node bridges before changing it.
3. **Never bypass SubsonicService** — 42 edges, 11 communities depend on it.
4. **ListeningEventCollector bridges 11 communities** — changes affect telemetry, tests, and playback simultaneously.
5. **Bucket 2 nodes are active** — `PaletteCache`, `Album`, `ListeningStats` are used but graph misses them. Use grep to verify before treating as dead code.
6. **Singleton pattern misses** — `PaletteCache.instance` is called in `now_playing_screen.dart` and `home_screen.dart`. Graph won't show this. Verify with grep.
7. **Factory constructor misses** — `Album.fromJson`, `ListeningStats.fromJson` used across providers. Graph won't show this. Verify with grep.
8. **Fragile community rule** — never expand Community 0 or 1. They're already bloated.
9. **Run `flutter analyze` after every single file change** — zero warnings before moving on.
10. **Run `build_runner` after any annotation change** — Riverpod codegen, Freezed, Drift.
11. **Never add platform channel calls** without verifying Linux runner community (Community 34: `fl_register_plugins`, `my_application.cc`).
12. **Progress bar rule** — `now_playing_screen.dart` progress bar must use `SliderTheme + Slider` matching mini player. Never use `_NeonTrackPainter` or `_GlassThumbShape` for the progress bar.

## 10. Feature Status (May 2026)

### Completed Features
- **FluidBackground Shader** — fully wired, `FluidShaderLoader`, `_FluidPainter`, `_FluidBackgroundState` all connected.
- **LRC Lyrics** — `LrcParser`, `LyricsController`, `LyricsBackground`, `LyricLine`, `SyncedLyrics` all present and grouped in their own communities.
- **Test Utilities** — `makeSong` and `pumpMicrotasks` extracted to `test/helpers/test_utils.dart`.

### In Progress Features (FEATURE_IMPLEMENTATION_PLAN.md)
Execute in this order:
1. **FEATURE 4 — Reshuffle Bug:** Fix stale `currentIndex` in `audio_handler.dart`. After shuffle completes, find current song by reference in new queue, not by pre-captured index.
2. **FEATURE 3 — Offline Filter:** Filter song list to downloaded-only when `ConnectivityResult.none`. Add offline banner. Guard `AudioHandler` queue against non-downloaded songs.
3. **FEATURE 2 — Playlist Performance:** Replace `ListView` with `ListView.builder`. Extract heavy widgets to `lib/screens/playlist/widgets/`. Show `_SongListSkeleton` immediately.
4. **FEATURE 1 — Lyrics Lag:** Defer `_subscribeToPosition` to `addPostFrameCallback`. Add `RepaintBoundary` around lyrics list. Pre-warm fluid shader in `main.dart`.
5. **FEATURE 5 — AI Shuffle Audit:** Audit only first. Fix after audit approved. 5 known bugs: timeout, queue clearing, session refresh, empty state, next song timing.

### Android Notification Controls (Implemented)
`AudioHandler` notification shows these 5 controls:
- Shuffle (custom action — toggles shuffle mode, icon changes)
- Previous
- Play/Pause
- Next
- Repeat Once (custom action — cycles LoopMode.off → one → all → off)

Drawable resources required in `android/app/src/main/res/drawable/`:
- `ic_shuffle.xml`
- `ic_shuffle_on.xml`
- `ic_repeat.xml`
- `ic_repeat_one.xml`

### UI Changes (Implemented)
- **Now Playing progress bar:** Uses `SliderTheme + Slider` matching mini player style. Removed `_NeonTrackPainter`. Uses `ThemeTokens.accent` for colors.
- **Mini player swipe:** `GestureDetector.onHorizontalDragEnd` wraps mini player. Swipe left = next, swipe right = previous. Threshold: 100 px/s velocity. Brief 50ms slide animation on gesture detection.

## 11. Testing Rules
- Unit tests for models (`fromJson`, `copyWith`).
- Service tests mock HTTP/Dio calls.
- Provider tests use `ProviderContainer` with overrides: `MockSubsonicService`, `MockOfflineService`, `MockAudioPlayer`.
- Widget tests verify all `AsyncValue` states: loading, error, data, empty.
- Always override platform-channel-touching providers to prevent `MissingPluginException`.
- Run `dart run mcp test <file>` after every single file change — not just at the end.

**Test coverage map (from graph):**
Communities with confirmed test coverage: `dart:async / dart:io / ../helpers/test_utils.dart`, `../core/app_constants.dart / applyShuffleAlgorithm`, `../controllers/lyrics_controller.dart`

## 12. Surprising Connections
Non-obvious couplings the graph found. Do not break these:

- `../fluid_background.dart` defines `FluidShaderLoader`, `_FluidPainter`, `FluidBackground`, `_FluidBackgroundState`, `shouldRepaint` — all wired through `now_playing_screen.dart`. [EXTRACTED]
- `PlayerProvider` calls `ListeningEventCollector` on play events — do not remove this call in refactors. [EXTRACTED]
- `AudioHandler` implements `Gapless Incremental Reordering` — use `ConcatenatingAudioSource.move()` not naive queue reassignment. [INFERRED]
- `settings_provider.dart` defines `_loadFromHive` — called from `player_provider.dart`. [EXTRACTED]
- `ListeningEventCollector` is semantically similar to `listening_log_service.dart` — keep their telemetry logic in sync. [EXTRACTED]
- `PaletteCache` is conceptually related to `Multi-Engine Theme System` — theme chain is active and confirmed. [EXTRACTED]
- `mini_player.dart` uses `AppRouteTransitions.slideUp()` — graph misses this (singleton pattern). Verify with grep if modifying either.

## 13. Known Bugs (from project_audit.md)
All bugs confirmed in source code. Fix status tracked in FEATURE_IMPLEMENTATION_PLAN.md.

| Bug ID | File | Description | Status |
|---|---|---|---|
| BUG-001 | `player_provider.dart` | `_trackChangeTimer` missing mounted/dispose guard | ✅ Approved |
| BUG-002 | `player_provider.dart` | `_playedDuration` drift & scrobble logic | ⚠️ Reworked |
| BUG-003 | `audio_handler.dart` | Shuffle rebuild performance | ⚠️ Reworked |
| BUG-004 | `audio_handler.dart` | `applyShuffleAlgorithm` sets stale `currentIndex` | 🔧 In Progress (FEATURE 4) |
| BUG-005 | `player_provider.dart` | `_persistState` timer fires multiple times | ✅ Approved |
| BUG-006 | `palette_cache.dart` | `PaletteCache` has no size limit | ✅ Approved |
| BUG-007 | `offline_service.dart` | Synchronous `File.existsSync()` per song on main thread | ✅ Approved |

## 14. Security Issues (from security audit)
| ID | File | Issue | Priority |
|---|---|---|---|
| SEC-001 | UI widgets | Service call directly from UI widget bypassing provider | HIGH |
| SEC-002 | `subsonic_service.dart` | Hardcoded fallback credentials | CRITICAL |
| SEC-003 | `subsonic_service.dart` | Sensitive URLs in production logs | HIGH |
| SEC-004 | `hive_boxes.dart` | Auth token storage review needed | MEDIUM |

## 15. Graph Query Reference
Run these before making structural changes:
```
/graphify query "what connects X to Y?"
/graphify explain "ComponentName"
/graphify path "ServiceA" "ServiceB"
/graphify query "what would break if I change X?"
/graphify query "which community does X belong to?"
```

After any code change:
```bash
graphify update .
```
Zero API cost — AST only. Verify no new isolated nodes were created.

## 16. MCP Server
graphify is registered as an MCP server in both Claude Code and Gemini CLI.
Use structured graph access via: `query_graph`, `get_node`, `get_neighbors`, `shortest_path`
Graph location: `graphify-out/graph.json`

## graphify Integration Rules
- ALWAYS read `graphify-out/GRAPH_REPORT.md` before reading any source files or running grep.
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw files.
- For cross-module questions, prefer `/graphify query`, `/graphify path`, `/graphify explain` over grep.
- After modifying code, run `graphify update .` to keep graph current.
- Never read `graphify-out/graph.json` directly — it is 925KB+ and will blow context limits. Use MCP queries instead.