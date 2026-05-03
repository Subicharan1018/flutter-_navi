# GEMINI.md — NaviVibe Project Rules
> Gemini CLI reads this file automatically at the start of every session.
> These rules govern ALL interactions with this codebase.
> Never violate these rules. If a task would require violating a rule, stop and ask.

---

## 📦 Project Identity

- **App name:** NaviVibe
- **Type:** Flutter music player for Subsonic-compatible servers
- **Language:** Dart / Flutter (beta channel, Dart 3.9+, Flutter 3.35+)
- **Target platforms:** Android, iOS (primary); potential desktop

---

## 🛠️ MCP Server Rules

1. The Dart MCP server (`dart mcp-server`) MUST be connected before any session.
   Run `/mcp` at the start of every session. If not 🟢 Ready, stop and fix it.

2. NEVER make a factual claim about the codebase without backing it with a
   Dart MCP tool call. "The code appears to..." is forbidden language.

3. Read `SKILLS.md` at the project root at the start of every session.
   The skills file defines exactly how to use each MCP tool for this project.

4. Tool call order for every session:
   ```
   1. /mcp          → verify server is ready
   2. analyze_files → get baseline errors/warnings
   3. run_tests     → get baseline test results
   ```

---

## 🏗️ Architecture Rules (Non-Negotiable)

### Layered Architecture
The layer order is strict. No skipping layers. No shortcuts.

```
UI (screens/, widgets/)
  ↓
State (providers/)
  ↓
Services (services/)
  ↓
Data (database/, Hive, network)
```

**Violations to flag immediately:**
- A `Screen` or `Widget` directly calling a `Service`
- A `Provider` directly reading from Drift or Hive (must go through a Service)
- A `Service` importing from `screens/` or `widgets/`
- Any file in `core/` importing from `providers/` or `screens/`

### Riverpod Rules
- All providers MUST use `@riverpod` code-generation annotations
- No `StateNotifier` (legacy) — use `Notifier` or `AsyncNotifier` only
- No `StateProvider` for complex state — use `Notifier`
- No `async` operations inside `build()` methods
- No `ref.read` inside `build()` — use `ref.watch`
- No global mutable static variables bypassing Riverpod

### Isolate Rules
- ALL heavy computation must run in isolates via `compute()` or `Isolate.run()`
- This includes: all 6 shuffle algorithms, BPM analysis, any sort of 100+ items
- Isolate worker functions MUST be top-level functions, never closures or class methods
- The `Song` model MUST contain only plain value types (String, int, double, bool)
  — no Flutter types, no non-sendable objects

### Service Rules
- Services receive dependencies via constructor injection (not `Ref` global lookups)
- Services MUST NOT import from `providers/` or `screens/`
- Every network call MUST have a `catch` block wrapping errors in `AppException`
- No `try {} catch (e) {}` with empty catch blocks — all errors must surface

---

## 🎵 Audio Engine Rules

- Shuffle MUST use incremental in-place reordering via `ConcatenatingAudioSource.move()`
- NEVER rebuild the entire `ConcatenatingAudioSource` during shuffle — this causes silence
- The currently playing song MUST be treated as an anchor during shuffle (never moved)
- All 6 shuffle algorithms must remain available: Fisher-Yates, Dithered Position,
  Merge-Shuffle, Weighted (Efraimidis-Spirakis), Album-Aware, Recency-Dampened
- State machine transitions MUST be exhaustive:
  `Idle → Loading → Buffering → Playing ↔ Paused → Stopped`
- `skipNext()` MUST transition through `Loading`, not directly to `Playing`

---

## 📊 Analytics & Data Integrity Rules

### ListeningEventCollector
- Fingerprint format is locked: `${song.id}@$queuePosition`
- Deduplication window is locked: 500ms
- Minimum play threshold: 2.0 seconds (no exceptions)
- Minimum co-play threshold for SongPairs: 5.0 seconds
- Session timeout: 30 minutes of inactivity → new UUID v4 sessionId
- Recency dampening: last 20 songs get 0.1× weight multiplier

### Database (Drift)
- Multi-step writes (PlayEvent + SongMetadata + SongPair) MUST use `transaction()`
- PlayEvents primary key MUST be UUID, not auto-increment integer
- SongMetadata is upserted on every "Song Started" — do not change this contract
- Never delete PlayEvents without running the purge utility logic check first

---

## 🔐 Security Rules

1. **No hardcoded credentials.** Any string literal matching `"casaos"`, `"password"`,
   `"secret"`, `"token"`, or `"api_key"` in non-test code is an immediate CRITICAL finding.

2. **Subsonic authentication salt MUST be randomly generated per request.**
   A fixed salt is a HIGH security finding.
   Correct: `List.generate(6, (_) => Random().nextInt(36).toRadixString(36)).join()`

3. **Hive boxes storing auth tokens MUST use `encryptionKey`.**
   Plaintext token storage = MEDIUM security finding.

4. **Server URLs MUST be validated to be HTTPS.** HTTP fallback is only allowed
   if explicitly toggled by the user in settings, and must show a warning.

5. **WebDAV uploads MUST use user-configured credentials.** No hardcoded fallbacks.

---

## 🎨 Design System Rules

- All UI code MUST use `AppThemeTokens` — no hardcoded `Color(0xFF...)` values in widgets
- All 6 themes must remain functional: Spotify, Aura, Frost, Neumorphic, Analog, Zen
- `FluidBackground` MUST use the GLSL fragment shader at `shaders/fluid_background.frag`
- Never replace the shader with a `CustomPainter` — the 60× CPU cost difference matters
- `bgSurfaceOpaque` MUST be pre-blended at the token level — never use `withOpacity()`
  on a surface color inside a widget (causes visual artifacts in dropdowns/menus)

---

## ⚡ Performance Rules

1. `palette_cache.dart` MUST enforce a maximum cache size.
   Acceptable: LRU eviction, max 500 entries, or configurable via settings.
   No cap = memory leak on large libraries.

2. Subsonic API calls that return song lists MUST paginate.
   Use `count` (max 500) and `offset` parameters. Never load the full library in one call.

3. `FluidBackground` MUST be wrapped in `RepaintBoundary` at every usage site.

4. All `AnimationController` instances MUST call `dispose()` in the widget's `dispose()`.

5. Never call `setState`, `ref.invalidate`, or any provider write inside:
   - A `build()` method
   - A scroll listener without debounce
   - A `StreamBuilder` builder without a guard

---

## 🧪 Testing Rules

1. Every new `Service` MUST have a corresponding test file before merging.
2. Every new shuffle algorithm variant MUST have a unit test covering:
   - Correct output length (no duplicates, no missing songs)
   - Anchor song remains in position (for gapless reorder)
   - Correct statistical behavior (weighted algorithms)
3. `ListeningEventCollector` tests MUST cover:
   - The 500ms deduplication window (use fake timers)
   - The 2s and 5s duration thresholds
   - The session timeout
4. Use `mocktail` or `mockito` for service mocking — never test with real network calls.
5. All tests MUST pass before any commit. `run_tests({})` is a pre-commit gate.

---

## 📝 Code Style Rules

1. Follow `dart format` conventions — `dart_format` check runs on every session.
2. No `// ignore:` lint suppressions without a comment explaining why.
3. No `dynamic` types in service or provider code.
4. All public API methods in services MUST have dartdoc comments.
5. Error messages in `AppException` MUST be user-readable strings, not stack traces.
6. Generated files (`*.g.dart`, `*.freezed.dart`) are never edited manually.
   Regenerate with `dart run build_runner build --delete-conflicting-outputs`.

---

## 🚫 Things Gemini MUST NOT Do

- Do NOT auto-commit any changes
- Do NOT modify `pubspec.yaml` without confirming the new version with `pub_dev_search` first
- Do NOT add dependencies without checking for conflicts with existing packages
- Do NOT edit `*.g.dart` or `*.freezed.dart` files — regenerate them instead
- Do NOT remove existing shuffle algorithms — all 6 must remain
- Do NOT change the `ListeningEventCollector` fingerprint format or thresholds
  without updating all related tests
- Do NOT replace `ConcatenatingAudioSource.move()` with a full playlist rebuild
- Do NOT hardcode any server URL, credential, or API key
- Do NOT access the network in unit tests — mock all HTTP calls

---

## 📁 Key File Reference

| What you need | Where to find it |
|---|---|
| Project architecture overview | `NAVIVIBE_AUDIT_PROMPT.md` (audit), architecture docs |
| MCP tool usage skills | `SKILLS.md` (project root) |
| All app constants | `lib/core/app_constants.dart`, `lib/core/constants.dart` |
| AppException types | `lib/core/app_exception.dart` |
| Hive box names | `lib/core/hive_boxes.dart` |
| Theme tokens | `lib/core/theme.dart` |
| Database schema | `lib/database/tables/` |
| Subsonic API client | `lib/services/subsonic_service.dart` |
| Audio engine | `lib/services/audio_handler.dart` |
| Analytics collector | `lib/services/listening_event_collector.dart` |
| Shader file | `shaders/fluid_background.frag` |
