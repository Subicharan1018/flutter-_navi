# 🌌 NaviVibe: Deep-Dive Technical Developer Context

NaviVibe is an ultra-premium, high-performance music client for the Subsonic ecosystem. This document provides a "heavily detailed" overview of every major subsystem, formula, and architectural rule within the codebase.

---

## 🏗️ 1. Core Architecture & Isolate Rules

NaviVibe follows a **Layered Clean Architecture** combined with a strict **Background-First Processing** rule.

### 🧵 Isolate Protocol
To maintain 120 FPS UI performance, all heavy computation is offloaded to OS-level isolates using `compute()` or `Isolate.run()`.
- **Top-Level Constraint**: Isolate workers MUST be top-level functions (e.g., `_standardShuffleIsolate`) to avoid capturing closures that contain non-sendable types.
- **Deep-Copying**: Arguments passed to isolates are deep-copied. Data classes like `Song` must contain only plain value types (String, int, double).
- **No Flutter Engine**: Workers should avoid `dart:ui` or Flutter-dependent libraries, relying solely on `dart:math` and pure Dart logic.

### 🧠 State Management (Riverpod 2.0)
- **Code Generation**: Uses `@riverpod` annotations to generate type-safe providers.
- **Logic Separation**: UI calls methods on Notifiers; Notifiers orchestrate Services; Services interact with the Database or API.
- **Provider Ref Tracking**: Services receive a `Ref` or specific dependencies via constructors to enable mocking in tests.

---

## 🔊 2. Audio Engine & Shuffle Specifications

The audio system is built on `just_audio` but heavily customized for "True Gapless" queue mutations.

### 🚀 Gapless Incremental Reordering
Unlike standard players that rebuild the entire playback source on shuffle (causing a silence gap), NaviVibe implements **In-Place Mutation**:
- **Anchor Logic**: When shuffling, the currently playing song is treated as an "anchor."
- **Selection-Sort Algorithm**: The system performs a selection-sort pass over the live `ConcatenatingAudioSource`. It finds the "live" position of each song and calls `_playlist!.move(fromIdx, targetIdx)`.
- **Decoder Stability**: Because the decoder is never torn down, the audio remains continuous even as the entire 1000+ song queue is being randomized around the playhead.

### 🎲 Shuffle Algorithms (Technical Specs)
1.  **Weighted (YouTube-Style)**:
    - **Formula**: $w = dynamicWeight.clamp(0.1, 10.0) \times (2.0 \text{ if starred}) + \frac{\text{rating}-1}{4} + \text{clamp}(\frac{\text{playCount}}{100}, 0, 1)$.
    - **Efraimidis-Spirakis Trick**: To achieve $O(n \log n)$ performance, it calculates a key $k = r^{1/w}$ where $r \in (0, 1]$. Songs are sorted descending by $k$.
2.  **Merge-Shuffle (Optimal Interleaving)**:
    - **Logic**: Groups songs by category, sorts categories by size (ascending), and folds them together.
    - **Interleave Primitive**: Splits the larger list into $N+1$ parts and inserts the $N$ elements of the smaller list into the gaps. This mathematically guarantees no back-to-back same-category songs if possible.
3.  **Dithered Position Shuffle**:
    - **Logic**: Assigns a global position score: $pos = offset + (i \times spacing) + dither$.
    - **Dither**: A $\pm 5\%$ random nudge that prevents the spread from feeling "too mechanical" while maintaining global genre spacing.
4.  **Recency-Dampened**:
    - **Window**: Maintains a `Set<String>` of the last 20 song IDs.
    - **Penalty**: Recently played songs receive a $0.1\times$ weight multiplier, making them $10\times$ less likely to appear in the next 20 tracks.

---

## 📊 3. Analytics & Intelligence (Data Integrity)

The **ListeningEventCollector** ensures that user statistics are accurate and "noise-free."

### 🛡️ Noise Filtering & Fingerprinting
- **The "Rapid-Fire" Guard**: To prevent double-counts from UI double-taps, the system creates a fingerprint `${song.id}@$queuePosition`. If the same fingerprint is seen within **500ms**, the event is collapsed.
- **Duration Thresholds**:
    - **Play Event**: Minimum 2.0s duration required to persist a play record.
    - **Song Pair**: Minimum 5.0s duration required to record a "co-play" relationship for recommendations.
- **Purge Logic**: A maintenance utility can strip "junk" events where `duration < 2s` AND `skipBefore50` is true.

### ⏱️ Session & Timeout
- **Timeout**: 30 minutes of inactivity triggers a new `sessionId` (UUID v4).
- **Repeat Tracking**: `onSongRepeated` increments a counter within a single open event rather than creating multiple database entries for back-to-back repeats.

---

## 🎨 4. Design System (ThemeTokens Engine)

NaviVibe uses a **Multi-Engine Tokenized System** to decouple aesthetics from UI code.

### 🎨 Theme Engines
1.  **Aura**: Album-art-driven mesh gradients using `shaders/fluid_background.frag`.
2.  **Frost**: iOS-style glassmorphism using `BackdropFilter` and `Color.withOpacity(0.3)`.
3.  **Neumorphic**: Tactile soft-UI with `neuLight` and `neuDark` shadow tokens.
4.  **Analog**: Warm retro palette (Aged Cream: `#F5ECD7`) with serif typography.
5.  **Zen**: Typography-led brutalism with pure monochrome accents.

### 🧩 Core Tokens (`AppThemeTokens`)
- `bgBase`: The absolute background layer.
- `bgSurface`: Secondary layer for cards/tiles.
- `bgSurfaceOpaque`: A pre-blended color ($bgSurface \text{ over } bgBase$) for UI elements that cannot handle translucency (e.g., dropdowns).
- `accent`: Primary interactive color (e.g., Spotify Green: `#1DB954`).

---

## 💾 5. Persistence & API Specification

### 🗄️ Database (Drift/SQLite)
- **Tables**:
    - `PlayEvents`: UUID-primary-key, tracks timestamps, duration, skip status, and context.
    - `SongMetadata`: Denormalized cache of Subsonic metadata for offline analytics queries.
    - `SongPairs`: Relational table tracking $Song A \to Song B$ transitions for the recommendation engine.
- **Sync**: Metadata is upserted on every "Song Started" event to ensure the local library stays current with the server.

### 🌐 Subsonic API (`SubsonicService`)
- **Authentication**: Salted MD5 tokens ($password + salt$).
- **Streaming**: Supports direct URLs and proxied streams. Proxied streams are used when transcoding is active (managed by `TranscodingService`).
- **WebDAV**: Used for "Replay" data backups. **Note**: Hardcoded fallback credentials ('casaos') have been removed for security; explicit user config is now mandatory.

---


