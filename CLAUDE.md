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

With the latest graph updates, be acutely aware of the **God Nodes** mapping to specific services and UI elements that have profound systemic impact.

## 4. God Nodes (Updated)
The `graphify` analysis identified the following files as "God Nodes" due to their immense betweenness centrality. Changes here ripple across the entire app.

1. **`replay_screen.dart` (52 edges) (NEW):** The UI orchestrator for replay statistics. Extensively connected to telemetry and data layers. Careless changes break data presentation logic. **Refactor Plan:** Split this node by extracting `_DailyListeningChart`, `_StatsCard`, `_ReplaySongRow`, and `_ReplayHeader` into `lib/screens/replay/widgets/`.
2. **`playlist_details_screen.dart` (52 edges) (NEW):** Highly connected UI component managing playlist interactions. Edits here affect offline states, playback flow, and transitions. **Refactor Plan:** Split this node by extracting `_ExpandedHeader`, `_LoadingHeader`, `_DownloadAllButton`, `_AddSongsRow`, and `_SongListSkeleton` into `lib/screens/playlist/widgets/`.
3. **`package:flutter_riverpod/flutter_riverpod.dart` (46 edges):** The foundational framework.
4. **`subsonic_service.dart` (46 edges) (NEW to top 10):** The network boundary. It bridges 11 different communities. Never bypass this for API calls. Breaking this breaks all remote data fetching.
5. **`ListeningStats` (43 edges) (NEW to top 10):** Core analytics model. Changes here require database, service, and provider synchronization.
6. **`ListeningEventCollector` (41 edges) (Promoted):** Telemetry and scrobble validation. Bridges 11 communities. Changes affect telemetry, tests, and playback simultaneously.
7. **`settings_screen.dart` (40 edges) (NEW to top 10):** Modifies global state parameters. Careless edits break application-wide configurations.
8. **`PlayerProvider` (40 edges):** The central state wrapper around the audio engine. Breaking this breaks the music flow.
9. **`package:flutter/material.dart` (38 edges):** Foundational UI framework.
10. **`mini_player.dart` (37 edges) (NEW to top 10):** Omnipresent UI component deeply coupled to `PlayerProvider` and routing across all screens.

**Rule for God Nodes:** Before changing a god node, verify dependents exhaustively. Do not add domain-specific feature bloat to these core files.

## 5. Service Boundaries (Community 61)
Community 61 contains the 6 most tightly coupled and critical services:
- **`AudioHandler`**: Background playback, lock-screen controls, and gapless queue manipulation.
- **`OfflineService`**: Manages file caching and offline playback flows.
- **`PlayerProvider`**: The reactive UI bridge to `AudioHandler`.
- **`SubsonicService`**: The strict boundary for all remote network calls. Note: **This is a top-level bridge crossing 11 communities (Communities 0, 15, 18, 21, 22, 25, 30, 31, 32, 43, 45).**
- **`Advanced Shuffle Algorithms`**: Isolate-based background sorting logic.
- **`ListeningEventCollector`**: Telemetry and scrobble validation.

## 6. Fragile Communities
The following communities have low cohesion (< 0.1), meaning they are weakly interconnected and potentially bloated. **Do not expand these communities.** If adding features, extract logic into focused Riverpod modules instead.
- **Community 0** - Cohesion improved to 0.07, but is still extremely fragile. Base UI components and download notification flows. Do not expand.
- **Community 1** - Cohesion 0.05. Core services and health reporting.
- **Community 2** - Cohesion 0.07. Shuffle API, stats responses, and shuffle repository.
- **Community 3** - Cohesion 0.07. Drift table companion logic (Analytics/Affinities).
- **Community 4** - Cohesion 0.06. Reusable widgets like bottom sheets and formatters.
- **Community 5** - Cohesion 0.08. Core exceptions (`AuthException`, `NetworkException`, etc.).
- **Community 6** - Cohesion 0.07. Stats and responses.
- **Community 7** - Cohesion 0.08. Theme styles and containers.
- **Community 8** - Cohesion 0.08. Database and download states.
- **Community 9** - Cohesion 0.09. Shuffle algorithms.

## 7. Theme System
The aesthetic core sits in an EXTRACTED path chain (confirmed, no longer just inferred):
`PaletteCache` → `Multi-Engine Theme System` → `FluidBackground Shader`.
Changing theme rules or color extraction directly impacts the GPU-accelerated fluid shader logic.

## 8. Isolated Nodes (Audit Complete)
The codebase has exactly **45 isolated nodes** (nodes with degree 0 in the graph, not 493 as previously claimed).

### Categorization:

**BUCKET 1 - INTENTIONALLY ISOLATED (27 nodes):** Platform boilerplate, auto-generated files, asset references.
- Android Gradle files: `build.gradle.kts` (root, app), `settings.gradle.kts`
- Linux ephemeral headers: 14 Flutter C++ platform bindings (`fl_*.h`, `generated_plugin_registrant.h`)
- Launcher icons: 10 asset variants (hdpi/mdpi/xhdpi/xxhdpi/xxxhdpi)
- Asset images: App logo, settings screenshot
- **Verdict:** ✅ Correct to isolate — auto-generated or build-system managed.

**BUCKET 2 - MISSING WIRES (12 nodes):** Core library classes and data models that *should* have edges but don't.
- **Constants & Utilities:** `AppConstants`, `AppException`, `Constants`, `PaletteCache`, `AppRouteTransitions`
- **Database Tables:** `AnalyticsTables`, `RecommendationTables`, `SearchHistoryTable`
- **Data Models:** `Album`, `DownloadState`, `ListeningStats`, `PlayEvent`
- **Verified active but missing graph edges:**
  - `AppRouteTransitions` → used in `mini_player.dart` (god node) via `AppRouteTransitions.slideUp()`
  - `Album` → used in `library_provider.dart` via `FutureProvider<List<Album>>`
  - `ListeningStats` → used in `listening_stats_provider.dart` via `StateNotifier<AsyncValue<ListeningStats>>`
  - `PaletteCache` → used as singleton in `now_playing_screen.dart`, `home_screen.dart`
- **Why isolated:** Graph captures file-level relationships (`palette_cache.dart` has 7 edges, `app_route_transitions.dart` would have calls) but misses class/symbol-level edges. Constructor calls, `fromJson` factories, and singleton instantiations are not tracked by AST extraction.
- **Status:** Requires `--mode deep` semantic extraction with aggressive INFERRED edge detection to rewire.
- **Action:** Run `/graphify . --mode deep --update` to add semantic edges (pending—requires graphify in PATH).

**BUCKET 3 - TEST UTILITIES (0 nodes):** No isolated test utilities found. Test helpers are correctly wired to test files.

**BUCKET 4 - DEAD CODE (6 nodes):** Launcher icon variants and platform scaffolding.
- **Legacy launcher icons:** `ic_launcher.png` (hdpi/mdpi/xhdpi/xxhdpi/xxxhdpi) — likely superseded by `launcher_icon.png` set
- **Linux platform header:** `my_application.h` (check CMakeLists.txt for linkage; likely dead or auto-generated)
- **Action:** 
  1. Delete `ic_launcher.png` variants if only `launcher_icon.png` is referenced in `pubspec.yaml` or flutter_launcher_icons config.
  2. Verify `my_application.h` linkage in `linux/CMakeLists.txt`. If unused, remove.
  3. Confirm deletion doesn't break builds.

**Rule:** When touching isolated UI or engine code, use `/graphify query` to understand its context. Bucket 2 nodes are core infrastructure—if truly unused, delete them. If used but not wired, trigger semantic reanalysis.

## 9. Safe Change Rules
Every AI agent must follow these rules:
- **`replay_screen.dart` and `playlist_details_screen.dart` are now god nodes** — treat them with same care as `settings_provider.dart`.
- **Never bypass `subsonic_service.dart` for API calls** — it now bridges 11 communities and acts as the single choke point.
- **`ListeningEventCollector` bridges 11 communities** — changes here affect telemetry, tests, and playback simultaneously.
- **Bucket 2 nodes (`PaletteCache`, `ListeningStats`, `Album`, core models) are actually active** — they have file-level edges (`palette_cache.dart` has 7 edges) but are missing symbol-level edges. Changes here ripple to multiple providers and services. Do not treat as dead code.
- **Singleton pattern misses:** `PaletteCache` is called as a singleton instance in multiple screens but AST doesn't detect the instantiation. If you modify `PaletteCache`, verify usage in `now_playing_screen.dart`, `home_screen.dart`, etc. via grep, not the graph.
- **Factory constructor misses:** Model classes (`Album`, `ListeningStats`) use `fromJson` factories that AST doesn't capture. They are heavily used in Riverpod providers and JSON deserialization. Changes here affect serialization across the entire app.
- Isolate UI from logic; do not add business logic to components in fragile communities.
- Preserve Hyperedges when working with offline capabilities (`OfflineService`, `app_database`, `playlist_cache_table`).
- Always run `flutter analyze` and `flutter pub run build_runner build` appropriately.

## 10. Testing Rules
- Unit tests for models (`fromJson`, `copyWith`).
- Service tests mock HTTP/Dio calls.
- Provider tests use `ProviderContainer` with overrides (`MockSubsonicService`, `MockOfflineService`, `MockAudioPlayer`).
- Widget tests verify UI for all `AsyncValue` states and interactions.
- **Test Utilities Refactor Plan:** The graph incorrectly attributed `makeSong` and `pumpMicrotasks` to `ListeningEventCollector`. They are actually duplicated across 5+ test files (e.g., `listening_event_collector_test.dart`, `audio_handler_shuffle_test.dart`, `download_connectivity_audit_test.dart`). They should be extracted into a shared `test/helpers/test_utils.dart` file, and imports in all affected test communities must be updated to use this new helper.

## 11. Surprising Connections
The graph extracted several non-obvious couplings. **Important caveat:** The graph captures file-level relationships well but misses symbol/class-level edges (singletons, factories, private constructors). For the following nodes, verify usage with grep rather than trusting the graph degree count.

**Confirmed EXTRACTED paths:**
- `ListeningEventCollector` --semantically_similar_to--> `listening_log_service.dart` [EXTRACTED - confirmed]
- `PaletteCache` --conceptually_related_to--> `Multi-Engine Theme System` [EXTRACTED - confirmed]

**Missing wires (file-level edges exist, symbol-level edges missing):**
- `PaletteCache` is a singleton instance used in `now_playing_screen.dart`, `home_screen.dart` — grep for `PaletteCache()` or `PaletteCache.instance`
- `ListeningStats` is instantiated via `fromJson` in `listening_stats_provider.dart` — grep for `ListeningStats.fromJson` or `map((data) => ListeningStats`
- `Album` is instantiated via `fromJson` in `library_provider.dart` and `search_provider.dart` — grep for `Album.fromJson`
- `AppRouteTransitions` (navigation utility) is called as `AppRouteTransitions.slideUp()` in `mini_player.dart` (god node) — graph shows 0 edges but it's active

**Misplaced test utilities (graph incorrectly attributed):**
- `makeSong`, `pumpMicrotasks`, `generateUuid` are duplicated across 5+ test files (not solely in `ListeningEventCollector`). Should be extracted into shared `test/helpers/test_utils.dart`.

## 12. Graph Query Reference
Run these queries before making structural changes to prevent architectural drift:
- `/graphify query "what connects X to Y?"`
- `/graphify explain "ComponentName"`
- `/graphify path "ServiceA" "ServiceB"`
- `/graphify query "what would break if I change X?"`

## 13. MCP Server
graphify is registered as an MCP server in both Claude Code and Gemini CLI.
Use structured graph access via: `query_graph`, `get_node`, `get_neighbors`, `shortest_path`
Graph location: `graphify-out/graph.json`