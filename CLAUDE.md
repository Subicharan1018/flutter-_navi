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

1. **`replay_screen.dart` (52 edges) (NEW):** The UI orchestrator for replay statistics. Extensively connected to telemetry and data layers. Careless changes break data presentation logic.
2. **`playlist_details_screen.dart` (52 edges) (NEW):** Highly connected UI component managing playlist interactions. Edits here affect offline states, playback flow, and transitions.
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

## 8. Isolated Nodes
The codebase currently has **493 isolated nodes** (down significantly from 997, marking major improvement). Key isolated nodes still include: `MainActivity`, `FluidShaderLoader`, `_FluidPainter`.
**Rule:** When touching isolated UI or engine code, use `/graphify query` to understand its context. Document or connect architecture where it runs completely standalone. This is progress but still needs work.

## 9. Safe Change Rules
Every AI agent must follow these rules:
- **`replay_screen.dart` and `playlist_details_screen.dart` are now god nodes** — treat them with same care as `settings_provider.dart`.
- **Never bypass `subsonic_service.dart` for API calls** — it now bridges 11 communities and acts as the single choke point.
- **`ListeningEventCollector` bridges 11 communities** — changes here affect telemetry, tests, and playback simultaneously.
- Isolate UI from logic; do not add business logic to components in fragile communities.
- Preserve Hyperedges when working with offline capabilities (`OfflineService`, `app_database`, `playlist_cache_table`).
- Always run `flutter analyze` and `flutter pub run build_runner build` appropriately.

## 10. Testing Rules
- Unit tests for models (`fromJson`, `copyWith`).
- Service tests mock HTTP/Dio calls.
- Provider tests use `ProviderContainer` with overrides (`MockSubsonicService`, `MockOfflineService`, `MockAudioPlayer`).
- Widget tests verify UI for all `AsyncValue` states and interactions.
- **Warning:** `ListeningEventCollector` currently defines `pumpMicrotasks`, `makeSong`, and `generateUuid` — these are test utilities living in the wrong place and should not be moved without updating all test communities.

## 11. Surprising Connections
The graph extracted several non-obvious couplings. Do not break these implicit bonds:
- `ListeningEventCollector` --semantically_similar_to--> `listening_log_service.dart` [EXTRACTED - confirmed]
- `ListeningEventCollector` --defines--> `pumpMicrotasks` [EXTRACTED - test utility misplaced]
- `PaletteCache` --conceptually_related_to--> `Multi-Engine Theme System` [EXTRACTED - confirmed]
- `ListeningEventCollector` --defines--> `makeSong` [EXTRACTED]
- `ListeningEventCollector` --defines--> `generateUuid` [EXTRACTED]

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