# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

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

## High‑Level Architecture Overview

The project follows a **Layered Clean Architecture** powered by **Riverpod** for state management:

1. **Presentation Layer** (`lib/screens`, `lib/widgets`)
   - UI widgets and full‑screen pages (e.g., `HomeScreen`, `NowPlayingScreen`).
   - Uses a custom `ThemeTokens` system for dynamic theming and GPU‑accelerated shaders.
2. **State Management Layer** (`lib/providers`)
   - Riverpod 2.x with `@riverpod` code‑generation.
   - `PlayerProvider` handles playback state, queue, and interactions with the audio service.
   - `LibraryProvider`, `SettingsProvider`, etc., expose reactive data to the UI.
3. **Service Layer** (`lib/services`)
   - `AudioHandler` (extends `BaseAudioHandler`) integrates `just_audio` and background playback.
   - `SubsonicService` talks to Navidrome/Subsonic servers (auth, fetching metadata).
   - `OfflineService` manages downloads and local caching.
4. **Data Layer** (`lib/database`, `lib/models`)
   - **Drift** (SQLite) stores relational metadata, listening stats, and playlist history.
   - **Hive CE** stores simple KV data such as auth tokens and user preferences.
   - Immutable model classes (generated via `freezed` or manual) represent songs, albums, etc.

All layers communicate via provider dependencies; UI watches reactive state (`ref.watch`) while callbacks use `ref.read`.

## Important Project Files

- `pubspec.yaml` – declares all runtime and dev dependencies (Flutter, Riverpod, just_audio, Drift, Hive, etc.).
- `analysis_options.yaml` – includes the Flutter lints package; enforce static code quality.
- `ARCHITECTURE.md` – detailed mermaid diagrams and component breakdown (refer to for visual references).
- `SKILLS.md` – contains the **Flutter Production Build & Audit** skill which enforces zero placeholders, proper error handling, and mandatory self‑audit/checklist after every change. Claude Code should respect those rules when modifying code.

## Testing Guidance

- Unit tests for models (`fromJson`, `copyWith`).
- Service tests mock HTTP/Dio calls.
- Provider tests use `ProviderContainer` with overrides for any platform channels, Hive, or Drift dependencies (see the test‑setup boilerplate in `SKILLS.md`).
- Widget tests verify UI for all `AsyncValue` states and interactions (loading, error, data). Use `testWidgets` and mock providers as needed.

## Code Generation

The project relies on generated files for Riverpod providers and immutable models. After adding new files or annotations, always run the build‑runner command above before building or testing.

## Miscellaneous

- No `.cursor` or Copilot instruction files are present, so no additional cursor rules need to be considered.
- Keep the `README.md` as the user‑facing entry point; it already outlines installation and contribution steps.
- When creating new files, follow the existing naming conventions (e.g., `*_provider.dart`, `*_service.dart`).
