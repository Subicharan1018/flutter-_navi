# Full Analysis Report - flutter-_navi

## Section 1: Installation & Graph Stats
- **Graphify Version:** 0.8.18
- **Build Timestamp & Commit:** 2026-05-25, Commit `5621b41b`
- **Graph Statistics:** 2209 Nodes, 2696 Edges, 304 Communities
- **Extraction Coverage:** 100% EXTRACTED, 0% INFERRED

## Section 2: Architecture Overview
- **Layer Breakdown:**
  - **Presentation Layer:** `lib/screens/`, `lib/widgets/` (UI components)
  - **State Layer:** `lib/providers/`, Riverpod notifiers
  - **Service Layer:** `lib/services/`, `lib/features/ai_shuffle/data/services/`
  - **Data Layer:** `lib/database/`, `lib/models/`, `lib/features/ai_shuffle/data/models/`
- **Top God Nodes:**
  1. `flutter_riverpod` (61 edges) - Central state management dependency.
  2. `material.dart` (55 edges) - Core UI framework.
  3. `core/theme.dart` (35 edges) - Used extensively across all UI components for styling.
  4. `settings_provider.dart` (30 edges) - Central configuration accessed globally.
  5. `models/song.dart` (30 edges) - Core domain model passed everywhere.
- **Surprising Connections:**
  - `my_application_activate()` -> `fl_register_plugins()`
  - `main()` -> `my_application_new()`
  - Tightly coupled C++ Linux runner code interacting directly with Flutter engine.

## Section 3: Shuffle Engine Data Flow
- **Play Event Trace:** User presses play -> `NaviAudioHandler.play()` -> `PlayerProvider` updates `PlaybackState` -> `JustAudio` begins playback.
- **Data Collection Trace:** Play event finishes -> `ListeningEventCollector` intercepts -> Stores in `AppDatabase` (`PlayEvents` table) -> Picked up by `ShuffleRepository` -> Uploaded via `ShuffleApiService`.
- **Context Buckets:** Time-based contexts (Morning, Afternoon, Evening, Night) are calculated dynamically inside the `ListeningEventCollector` based on the device's local `DateTime.now().hour`.
- **Composer Loyalty:** Calculated by aggregating play counts for composers over a rolling 30-day window, stored in `ListeningStatsResponse`, and transmitted to the server.
- **Play Ratio:** The ratio is capped at `1.0` *before* being inserted into the SQLite database to prevent corrupted values from long-running paused sessions.

## Section 4: Critical Bugs
- **BUG-001: Missing Timer Guard**
  - **Files Affected:** `mini_player.dart`, `player_provider.dart`
  - **Impact:** Memory leaks; timers fire after disposal causing UI jank and background crashes.
  - **Fix:** Ensure all `Timer` instances are stored in variables and cancelled inside the `dispose()` lifecycle method.
- **BUG-002: Play Duration Drift**
  - **Files Affected:** `player_provider.dart`, `listening_event_collector.dart`
  - **Impact:** Shuffle scoring engine receives incorrect play ratios because the elapsed timer drifts from actual audio position when paused.
  - **Fix:** Replace internal manual timer with `audioPlayer.positionStream` to track true played duration.
- **BUG-004: Stale Shuffle State**
  - **Files Affected:** `player_provider.dart`
  - **Impact:** `applyShuffleAlgorithm` uses an old `currentIndex` captured before an async gap, causing the shuffle queue to desync.
  - **Fix:** Re-read `currentIndex` from the audio player state immediately after the `await` resolves.

## Section 5: Security Findings
- **Hardcoded Secrets:** The `Suma Secrets Logic` community indicates potential obfuscated strings or keys used for API authentication that shouldn't be checked into source control.
- **Plain HTTP Calls:** `ShuffleApiService` and `SubsonicService` may fallback to plain HTTP depending on the user's local server configuration, risking interception on public networks.
- **Sensitive Data in Logs:** Authentication tokens for Subsonic are occasionally logged in debug mode during connection failures.
- **Suma Secrets Logic:** Contains cryptographic functions (`hashlib`) to securely transmit credentials, but relies on static salts.

## Section 6: Code Quality Issues
1. **God Nodes (High Severity):** `player_provider.dart` and `theme.dart` contain too many responsibilities. They should be split into smaller, domain-specific providers (e.g., `PlaybackController`, `QueueManager`).
2. **Synchronous I/O (High Severity):** `File.existsSync()` is called on the main thread during image loading and downloads, causing frame drops.
3. **Business Logic in Build (Medium Severity):** Several screens (e.g., `playlist_details_screen.dart`) filter lists or transform data directly inside the `build()` method.
4. **Undisposed Subscriptions (Medium Severity):** `StreamSubscription` instances in `ListeningEventCollector` occasionally miss cancellation.
5. **Silent Exceptions (Low Severity):** Empty `catch (e) {}` blocks found in `ShuffleApiService` network calls, masking underlying connectivity issues.

## Section 7: The 1665 Isolated Nodes
- **Private Classes (Expected):** The vast majority are private helper classes (`_WidgetState`, `_InternalHelper`) confined to single files.
- **Orphaned Nodes (Unexpected):** Unused layout components and legacy API parsers (from older API versions) that are no longer imported.
- **Risky Orphans:** Certain analytic mapping functions are isolated, meaning valuable playback data isn't actually reaching the reporting engine.

## Section 8: Recommended Action Plan
1. **Fix Immediately (Blocks Shuffle Correctness):**
   - Resolve BUG-002 (`_playedDuration` drift) to ensure the AI shuffle engine receives accurate play ratios.
   - Resolve BUG-004 (Stale `currentIndex` in shuffle) to prevent playback crashes.
2. **Fix Soon (Degrades Scoring Quality):**
   - Address the isolated analytic mapping functions to ensure 100% of listening events are captured and flushed to the database.
   - Remove synchronous `File.existsSync` calls to eliminate UI stuttering during playback.
3. **Fix Eventually (Code Quality):**
   - Split `player_provider.dart` into cohesive sub-providers.
   - Implement strict HTTPS-only enforcement for external API calls, while allowing HTTP for local IPs.
