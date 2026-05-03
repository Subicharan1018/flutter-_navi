# NaviVibe Agent Skills
> Place this file at the root of your project.
> Gemini CLI reads it automatically before every session.
> These skills define HOW to use the Dart MCP server tools correctly
> for this specific codebase. Follow them exactly.

---

## SKILL 1 — Static Analysis (Always Your First Move)

**When to use:** Before reading any file. Before making any claim.
**What it does:** Gives you ground-truth errors, warnings, hints, and lint
violations across all 62 files simultaneously.

```
analyze_files({ "path": "lib/", "options": ["--fatal-infos", "--fatal-warnings"] })
```

**Rules:**
- Run this ONCE at the start of a session and save the full output.
- Do NOT re-run per-file. The project-wide run already covers everything.
- Exclude generated files from style findings: `*.g.dart`, `*.freezed.dart`
- If you want to auto-fix safe issues, follow with:
  ```
  dart_fix({ "paths": ["lib/"] })
  ```
  Then re-run `analyze_files` to confirm no regressions were introduced.

**What to look for:**
- `error` severity → must be fixed before any new work
- `warning` severity → architecture violations, potential bugs
- `info/hint` severity → code quality, unused imports, dead code
- `unawaited_futures` lint → silent async failure points in services/providers

---

## SKILL 2 — Symbol Resolution (Verify Before You Claim)

**When to use:** Any time the architecture docs claim a class, method, annotation,
or API exists. Do not trust the docs. Verify with this tool.

```
resolve_symbol({ "symbol": "SymbolName" })
resolve_symbol({ "symbol": "ClassName.methodName" })
```

**Key symbols to resolve for this project:**

```dart
// Audio engine
resolve_symbol("ConcatenatingAudioSource.move")
resolve_symbol("BaseAudioHandler")
resolve_symbol("AudioHandler")
resolve_symbol("Isolate.run")

// State management
resolve_symbol("riverpod")      // confirms @riverpod annotation
resolve_symbol("Ref")           // Riverpod Ref type

// Models
resolve_symbol("Song")          // must have only plain value types
resolve_symbol("PlayEvent")
resolve_symbol("SongPair")

// Database tables
resolve_symbol("PlayEvents")    // Drift table — UUID primary key?
resolve_symbol("SongMetadata")  // Drift table — denormalized cache?
resolve_symbol("SongPairs")     // Drift table — A→B transitions?

// Design system
resolve_symbol("FluidBackground")    // must use shader, not CustomPainter
resolve_symbol("AppThemeTokens")
resolve_symbol("bgSurfaceOpaque")
```

**Rules:**
- If `resolve_symbol` returns nothing → the symbol does not exist → HARD FINDING.
- "Symbol not found" is the most important result this tool can return.
- Always note the import path returned — it tells you if the dependency is
  actually installed or just referenced.

---

## SKILL 3 — Test Execution (Find What Actually Works)

**When to use:** At session start (full suite), and after fixing any bug.

```
// Full suite
run_tests({})

// Targeted runs for high-risk services
run_tests({ "testPathPattern": "audio_handler" })
run_tests({ "testPathPattern": "listening_event_collector" })
run_tests({ "testPathPattern": "recommendation" })
run_tests({ "testPathPattern": "subsonic" })
run_tests({ "testPathPattern": "shuffle" })
run_tests({ "testPathPattern": "drift" })
```

**Interpreting results:**
- Any test throwing `UnimplementedError` at runtime → mark as 🚧 STUB
- A service with ZERO test files → mark as ❌ NO TESTS
- Flaky tests (pass on first run, fail on second) → mark as ⚠️ RACE CONDITION

**High-risk services that MUST have tests:**
- `audio_handler.dart` — gapless reorder, state machine transitions
- `listening_event_collector.dart` — fingerprint deduplication, thresholds
- `recommendation_service.dart` — SongPairs query correctness
- `subsonic_service.dart` — auth, error handling, all endpoints

---

## SKILL 4 — Code Formatting Check

**When to use:** As part of the baseline audit, and before any PR.
Run in CHECK MODE only — do not auto-apply during an audit.

```
dart_format({ "paths": ["lib/"], "setExitIfChanged": true })
```

Files that would be changed = not following `dart format` conventions.
List them as a CI hygiene finding. Do not reformat during the audit unless
explicitly asked to.

**Excluded from formatting audit:**
- `lib/**/*.g.dart`
- `lib/**/*.freezed.dart`
- `lib/database/app_database.g.dart`

---

## SKILL 5 — Dependency Audit

**When to use:** When checking if packages are outdated, deprecated, or replaced.

```
pub_dev_search({ "query": "just_audio" })
pub_dev_search({ "query": "riverpod latest" })
pub_dev_search({ "query": "drift sqlite flutter" })
pub_dev_search({ "query": "audio_service" })
pub_dev_search({ "query": "hive flutter" })
pub_dev_search({ "query": "dio dart" })
pub_dev_search({ "query": "flutter_animate" })
```

**Flags to raise:**
- Package more than 2 major versions behind current → HIGH
- Package with published deprecation notice → CRITICAL
- Package replaced by an official successor → HIGH
- Package with no updates in 18+ months and open critical issues → MEDIUM

**Cross-reference:** Always compare search results against `pubspec.yaml`
version constraints. A `^1.0.0` constraint that blocks a `3.x` release is
a silent version lock.

---

## SKILL 6 — Runtime Introspection (When App Is Running)

**When to use:** ONLY when the Flutter app is running in debug mode.
These tools connect to the live Dart VM — they cannot be simulated.

```
get_runtime_errors({})       // All current Dart VM errors
get_selected_widget({})      // Widget tree at current selection
hot_reload({})               // Apply code changes without restart
hot_restart({})              // Full restart preserving device state
```

**Rules:**
- If the app is NOT running, state: `"Runtime introspection skipped — app not in debug mode."`
- Do NOT fabricate runtime behavior from reading source code alone.
- `get_runtime_errors` should be the FIRST call in any debugging session.
- After applying a fix, always `hot_reload` and re-run `get_runtime_errors`
  to confirm the fix worked before claiming it is resolved.

**For this project specifically, check:**
- Any `RenderFlex overflow` errors (widget layout bugs)
- Any `StateError: Ref.read was called after dispose` (Riverpod lifecycle bugs)
- Any `ConcatenatingAudioSource` index errors (shuffle reorder bugs)
- Any `Drift` database lock errors (concurrent write bugs)

---

## SKILL 7 — Call-Chain Tracing (No Assumption Rule)

**When to use:** Any time you need to verify a feature is "connected end-to-end."
A service file existing does NOT mean it is called. Trace every link.

**The 4-step protocol:**

```
Step 1: resolve_symbol on the service's public methods
        → confirms the API surface exists

Step 2: Search provider files for calls to those methods
        → confirms the service is consumed by state management

Step 3: Search screen files for references to those providers
        → confirms the data reaches the UI

Step 4: Only then conclude: ✅ CONNECTED | ⚠️ PARTIAL | ❌ DEAD END
```

**Dead end signals:**
- Service method exists but `resolve_symbol` shows zero references in `lib/providers/`
- Provider computed value exists but no screen imports that provider
- Screen imports provider but only reads a different value than the one the service provides

**Apply to these high-risk pipelines:**
- `bpm_analyzer_service` → any provider → any screen widget
- `recommendation_service` + `SongPairs` → `made_for_you_screen`
- `replay_upload_service` → `replay_provider` → `replay_screen`
- `transcoding_service` → `subsonic_service` stream URL selection
- `offline_service` file state → `offline_screen` UI state

---

## SKILL 8 — Security Pattern Scanning

**When to use:** Security audit of auth, storage, and network code.
`analyze_files` does NOT catch hardcoded credentials — this skill fills that gap.

**Files to read fully:**
- `lib/services/subsonic_service.dart`
- `lib/services/replay_upload_service.dart`
- `lib/core/constants.dart`
- `lib/core/app_constants.dart`
- `lib/core/hive_boxes.dart`
- `lib/main.dart`

**Patterns that are findings if present:**

| Pattern | Severity | What to look for |
|---|---|---|
| Hardcoded password/token | CRITICAL | String literals: `"casaos"`, `"password"`, `"secret"` |
| Static MD5 salt | HIGH | `md5.convert(utf8.encode(password + "fixedstring"))` |
| WebDAV embedded creds | HIGH | URL strings with `user:pass@hostname` |
| Hive box without encryption | MEDIUM | `Hive.openBox('auth')` with no `encryptionKey` |
| HTTP fallback allowed | MEDIUM | `http://` accepted in server URL field |
| No URL sanitization | MEDIUM | Raw user input used directly in `Uri.parse()` |
| Token in plaintext file | HIGH | `File(...).writeAsString(token)` |

**For Subsonic auth specifically:**
The salt must be generated per-request using `Random()`. If you see:
```dart
final salt = "some_fixed_string";  // ❌ Static salt — HIGH severity
```
vs:
```dart
final salt = List.generate(6, (_) => Random().nextInt(36).toRadixString(36)).join(); // ✅
```
The first is a finding. The second is correct.

---

## SKILL 9 — Performance Risk Checklist

**When to use:** Performance audit of caching, memory, and rendering code.

**`palette_cache.dart`:**
- Look for a `maxSize` field, `LruMap`, or manual eviction logic
- If none found: calculate risk = `avgPaletteSize × librarySize`
- A 10,000-album library with 5 colors per palette × 32 bytes = ~1.6MB minimum,
  but object overhead in Dart can 10× this

**`library_provider.dart`:**
- Look for `offset`, `count`, `size`, or `limit` in Subsonic API calls
- The Subsonic `getSongs` endpoint supports `count` (max 500) and `offset` for pagination
- No pagination = full library loaded into memory on startup

**`fluid_background.dart`:**
- Look for `controller.dispose()` inside `@override void dispose()`
- Look for `RepaintBoundary` wrapping the shader widget in parent screens
- Look for `ticker.dispose()` if using `SingleTickerProviderStateMixin`

**Scroll listener rule:**
- NEVER call `setState`, `ref.invalidate`, or `ref.read(provider.notifier).method()`
  inside a `ScrollController.addListener` callback without a debounce
- Find every `addListener` in screens and verify it is debounced or only reads,
  never writes

---

## SKILL 10 — Isolate Correctness Verification

**When to use:** Verifying that shuffle algorithms and heavy computation actually
run off the main thread.

**What makes a valid isolate worker for this project:**

```dart
// ✅ CORRECT — top-level function, pure Dart types
Future<List<Song>> _weightedShuffleIsolate(List<Song> songs) async { ... }

// Called via:
final result = await compute(_weightedShuffleIsolate, songs);
// OR
final result = await Isolate.run(() => _weightedShuffleIsolate(songs));
```

```dart
// ❌ WRONG — closure captures non-sendable state
final result = await compute((songs) {
  return someService.shuffle(songs); // captures someService — will throw SendPort error
}, songs);

// ❌ WRONG — class method, not top-level
final result = await compute(_shuffle, songs); // where _shuffle is a class method
```

**`Song` model validation:**
Run `resolve_symbol("Song")` and verify EVERY field is one of:
`String`, `int`, `double`, `bool`, `List<String>`, `List<int>`, `List<double>`

If any field is: `Color`, `Widget`, `BuildContext`, `Key`, `GlobalKey`,
`AnimationController`, or any Flutter type → CRITICAL finding.
The isolate will throw a `SendPort` error at runtime when passed a `Song`.

---

## SKILL USAGE QUICK-REFERENCE

| I want to... | Use this skill | MCP tool |
|---|---|---|
| Start any session | SKILL 1 | `analyze_files` |
| Verify a claimed API exists | SKILL 2 | `resolve_symbol` |
| Check what tests pass | SKILL 3 | `run_tests` |
| Check formatting | SKILL 4 | `dart_format` |
| Check if packages are current | SKILL 5 | `pub_dev_search` |
| Debug a running app | SKILL 6 | `get_runtime_errors` |
| Verify a feature is wired up | SKILL 7 | `resolve_symbol` chain |
| Find hardcoded secrets | SKILL 8 | File read + pattern match |
| Audit memory/render perf | SKILL 9 | File read + analysis output |
| Verify isolate correctness | SKILL 10 | `resolve_symbol("Song")` |
