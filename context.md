# NaviVibe Context & Architecture

This document provides the full context, architecture, and project flow of the NaviVibe application, assembled using the `graphify` knowledge graph and associated documentation.

## 1. Project Overview
- **App Name:** NaviVibe
- **Purpose:** A high-performance, aesthetically pleasing music player built for Subsonic-compatible servers.
- **Tech Stack:** Flutter, Riverpod (State Management), just_audio (Audio Engine), Drift (SQLite Database), Hive (Key-Value Store), custom Fragment Shaders.
- **Entry Point:** `lib/main.dart`
- **Platform Targets:** Android, Linux.

## 2. High-Level Architecture
The project follows a **Layered Clean Architecture** pattern, ensuring a separation of concerns between UI, business logic, and data handling. State management is powered by **Riverpod 2.0** with code generation for safety and performance.

### Component Breakdown
1. **Presentation Layer (`lib/screens`, `lib/widgets`)**:
   - **Screens**: Functional pages like `HomeScreen`, `NowPlayingScreen`, and `LibraryScreen`.
   - **Widgets**: Atomic, reusable components (e.g., `FluidBackground`, `AppScaffold`).
   - **Rules**: Use `ref.watch()` inside `build()` to react to state changes. Never use `ref.read()` in `build()`.
2. **State Management Layer (`lib/providers`)**:
   - **Providers**: `PlayerProvider` (manages playback state), `LibraryProvider` (manages local/remote metadata), `SettingsProvider` (manages preferences).
   - **Rules**: Use `ref.read()` inside event handlers and callbacks.
3. **Service Layer (`lib/services`)**:
   - **AudioHandler**: Extends `BaseAudioHandler` to manage background playback, media notifications, and lock-screen controls via `just_audio`.
   - **SubsonicService**: The boundary for all remote network calls.
   - **OfflineService**: Manages track downloads and local playback logic.
4. **Data Layer (`lib/database`, `lib/models`)**:
   - **Drift (SQLite)**: Used for complex relational data like library metadata, search history, and listening stats.
   - **Hive**: High-speed NoSQL storage for settings, auth tokens, and UI state.
   - **Models**: Immutable data classes (generated via `freezed` or similar) representing Songs, Albums, and Artists.

## 3. Project Flow (Core Data Flows)

### A. Music Playback Flow
When a user interacts with the UI to play a song:
1. **User (UI)** taps "Play Song".
2. **PlayerProvider** intercepts the action and calls **SubsonicService** to get the Stream URL.
3. **SubsonicService** returns the URL (Direct or Proxied).
4. **PlayerProvider** passes a `MediaItem` to **AudioHandler**.
5. **AudioHandler** tells **JustAudio** to set the audio source (`UrlSource`).
6. **JustAudio** starts playback and notifies **AudioHandler**.
7. **AudioHandler** updates the `PlaybackState`.
8. **PlayerProvider** reads the state and updates the UI (Progress Bar, Icons).

### B. Offline Sync Flow
1. **Subsonic Server** pushes data to **OfflineService**.
2. **OfflineService** stores the physical file in the **Local Filesystem** and metadata in the **Drift Database**.
3. **Drift Database** notifies the **LibraryProvider**.
4. **LibraryProvider** updates the **Library Screen** UI.

### C. State Machine
- `Idle` -> `Loading` (on `play(track)`)
- `Loading` -> `Buffering`
- `Buffering` -> `Playing`
- `Playing` -> `Paused` (on `pause()`) / `Stopped` (on `stop()`) / `Loading` (on `skipNext()`)
- `Paused` -> `Playing` (on `resume()`)

## 4. Graphify Insights & Structural Context

### God Nodes (Most Connected Abstractions)
These nodes act as cross-community bridges and are the core abstractions of the app.
1. `package:flutter_riverpod/flutter_riverpod.dart` (75 edges)
2. `package:flutter/material.dart` (67 edges)
3. `playlist_details_screen.dart` (52 edges)
4. `replay_screen.dart` (52 edges)
5. `../../models/song.dart` (48 edges)
6. `../../../core/theme.dart` (45 edges)
7. `../../providers/settings_provider.dart` (44 edges)

*Refactoring Priority:* God Nodes like `replay_screen.dart` and `playlist_details_screen.dart` need UI component extraction to reduce God Node Bloat.

### Service Boundaries (Core Cluster)
- **`AudioHandler`**: Background playback, lock-screen/notification controls, gapless queue.
- **`SubsonicService`**: Strict boundary for all remote network calls (42 edges, 11 communities). Never bypass for API calls.
- **`ListeningEventCollector`**: Telemetry and scrobble validation. Bridges 11 communities.

### Audio Engine & Shuffle Intelligence
- **Gapless Reordering**: NaviVibe leverages `ConcatenatingAudioSource.move()` to shift tracks incrementally during a shuffle while the decoder is running to avoid "Shuffle-Gap" audio drops.
- **Advanced Algorithms**: 6 distinct shuffle algorithms processed in background isolates (Fisher-Yates, Dithered Position, Merge-Shuffle, Weighted, Album-Aware, Recency-Dampened).

### Surprising Connections
- `../fluid_background.dart` defines `FluidShaderLoader`, `_FluidPainter`, `FluidBackground`, `_FluidBackgroundState`, `shouldRepaint` — all wired through `now_playing_screen.dart`.
- `PlayerProvider` calls `ListeningEventCollector` on play events.
- `mini_player.dart` uses `AppRouteTransitions.slideUp()`.

## 5. Known Smells & Architectural Technical Debt (May 2026 Audit)

1. **SMELL-001 (God Node Bloat):** `replay_screen.dart` and `playlist_details_screen.dart` inject massive API payloads directly into UI controllers. Need refactoring into isolated widget files.
2. **SMELL-002 (Fragile Communities):** Certain communities (like Now Playing & Queue UI) mix presentation widgets, platform channels, and data serialization into single blobs.
3. **SMELL-003 (ListeningEventCollector Responsibility Creep):** Production telemetry logs maintain test helper artifacts like `pumpMicrotasks` and `makeSong`.
4. **SEC-001 (High Security Risk):** Service calls are made directly from UI widgets (e.g. `AlbumCard`, `SongTile`) bypassing the state management layer.

## 6. Development & Graphify Rules
- **Rule 1:** Always read `graphify-out/GRAPH_REPORT.md` before making structural changes.
- **Rule 2:** Never use `ref.read()` in `build()` methods.
- **Rule 3:** Never bypass `SubsonicService` for any API requests or `AudioHandler` for playback queue operations.
- **Rule 4:** `OfflineService` owns all file path logic.
- **Rule 5:** After any code change, run `graphify update .` to keep the AST graph current.

---
*Generated using graphify analysis from the NaviVibe knowledge graph.*
