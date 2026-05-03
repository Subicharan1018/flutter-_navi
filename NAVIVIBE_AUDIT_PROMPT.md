# NaviVibe Full Codebase Audit Prompt
> Paste this entire file into Gemini CLI from your project root.
> The Dart MCP server must be connected and 🟢 Ready before proceeding.

---

## ⚙️ STEP 0 — VERIFY MCP BEFORE ANYTHING ELSE

Run `/mcp` right now. Confirm the `dart` server is listed as 🟢 Ready.
If it is not ready, **STOP** and report the error. Do not proceed with guesses.

Paste the full `/mcp` tool list at the top of your report under
`## Confirmed MCP Tools Available`. This is mandatory — it defines exactly
which tools you are permitted to use for this audit.

Expected tools (non-exhaustive):

- `analyze_files` / `dart_fix` / `dart_format`
- `resolve_symbol`
- `run_tests`
- `pub_dev_search` / `add_dependency` / `remove_dependency`
- `get_runtime_errors` / `get_selected_widget` / `hot_reload` / `hot_restart`
- `get_diagnostics` / `apply_fixes`

---

## 🗂️ PROJECT CONTEXT

**App:** NaviVibe — ultra-premium Flutter music client for Subsonic-compatible servers
(Navidrome, Airsonic, Gonic).

**Stack:** Flutter/Dart · Riverpod 2.0 · just\_audio + audio\_service · Drift (SQLite) ·
Hive · Dio/HTTP · Fragment Shaders · Subsonic API

**Architecture:** Layered Clean Architecture — UI → Providers → Services → Data.
All heavy computation must run in background isolates.

**File tree (62 files, 10 directories):**

```
lib/
├── core/
│   ├── app_constants.dart
│   ├── app_exception.dart
│   ├── constants.dart
│   ├── hive_boxes.dart
│   ├── navigation_transitions.dart
│   ├── palette_cache.dart
│   └── theme.dart
├── database/
│   ├── app_database.dart
│   ├── app_database.g.dart
│   ├── daos/
│   └── tables/
│       ├── analytics_tables.dart
│       ├── playlist_cache_table.dart
│       ├── recommendation_tables.dart
│       └── search_history_table.dart
├── models/
│   ├── album.dart
│   ├── play_event.dart
│   ├── playlist.dart
│   ├── song.dart
│   └── song_pair.dart
├── providers/
│   ├── library_provider.dart
│   ├── player_provider.dart
│   ├── replay_provider.dart
│   ├── search_provider.dart
│   └── settings_provider.dart
├── screens/
│   ├── edit_playlist_screen.dart
│   ├── favorites_screen.dart
│   ├── home_screen.dart
│   ├── library_screen.dart
│   ├── made_for_you_screen.dart
│   ├── new_releases_screen.dart
│   ├── now_playing_screen.dart
│   ├── offline_screen.dart
│   ├── playlist_details_screen.dart
│   ├── queue_screen.dart
│   ├── replay_screen.dart
│   ├── search_screen.dart
│   ├── settings_screen.dart
│   └── song_picker_screen.dart
├── services/
│   ├── audio_handler.dart
│   ├── bpm_analyzer_service.dart
│   ├── cache_settings_service.dart
│   ├── listening_event_collector.dart
│   ├── playlist_cache_service.dart
│   ├── recommendation_service.dart
│   ├── replay_gain_service.dart
│   ├── replay_upload_service.dart
│   ├── search_history_service.dart
│   ├── subsonic_service.dart
│   └── transcoding_service.dart
├── widgets/
│   ├── add_to_playlist_dialog.dart
│   ├── album_card.dart
│   ├── app_scaffold.dart
│   ├── create_playlist_dialog.dart
│   ├── mini_player.dart
│   ├── options_menu.dart
│   ├── progress_bar.dart
│   ├── song_tile.dart
│   └── theme_selector.dart
├── fluid_background.dart
├── offline_service.dart
└── main.dart
```

---

## 📐 ARCHITECTURE CLAIMS TO VERIFY

The architecture docs claim the following. **Verify every single one using MCP tools.**
Do not assume any claim is true because the docs say so.

### Audio Engine
1. `AudioHandler` extends `BaseAudioHandler` from `audio_service`
2. Gapless reorder uses `ConcatenatingAudioSource.move()` — NOT a full playlist rebuild
3. Currently playing song is held as an "anchor" during shuffle (never moved)
4. A selection-sort pass runs over the live `ConcatenatingAudioSource`
5. The decoder is never torn down during reorder (audio remains continuous)
6. All 6 shuffle algorithms run in background isolates via `compute()` or `Isolate.run()`
7. All isolate worker functions are top-level (not closures or class methods)

### Shuffle Algorithms (All 6 Must Exist)
8. **Fisher-Yates** — standard O(n) uniform random pass
9. **Dithered Position** — `pos = offset + (i × spacing) + dither`, dither = ±5%
10. **Merge-Shuffle** — Ruud van Asseldonk optimal interleaving, groups by category
11. **Weighted** — Efraimidis-Spirakis: `k = r^(1/w)`, sort descending by k
12. **Album-Aware** — randomises albums, preserves internal track order
13. **Recency-Dampened** — `Set<String>` of last-20 IDs, 0.1× weight multiplier

### Weight Formula
14. Formula: `w = dynamicWeight.clamp(0.1, 10.0) × (2.0 if starred) + (rating-1)/4 + clamp(playCount/100, 0, 1)`

### ListeningEventCollector
15. Fingerprint format: `${song.id}@$queuePosition`
16. 500ms deduplication window for same fingerprint
17. 2.0s minimum play duration before persisting a PlayEvent
18. 5.0s minimum duration before recording a SongPair (co-play)
19. 30-minute inactivity timeout generates a new UUID v4 sessionId
20. Recently played songs (last 20) receive 0.1× weight multiplier

### Riverpod & Architecture
21. All 5 providers use `@riverpod` code-generation annotations
22. No provider directly accesses Drift or Hive (must go through a Service)
23. No `async` operations inside a provider `build()` method
24. No global mutable state (static variables, singletons) bypassing Riverpod

### Data Layer
25. `Song` model contains ONLY plain value types (String, int, double) — no Flutter types
26. `PlayEvents` Drift table has UUID primary key
27. `SongMetadata` table exists as denormalized cache
28. `SongPairs` table tracks A→B song transitions
29. Subsonic auth uses salted MD5: `MD5(password + random_salt)`
30. Hardcoded `casaos` credentials have been removed

### Design System
31. All 6 themes implemented: Spotify, Aura, Frost, Neumorphic, Analog, Zen
32. `bgSurfaceOpaque` is pre-blended (bgSurface over bgBase), not transparent
33. `FluidBackground` uses a GLSL fragment shader at `shaders/fluid_background.frag`
34. `FluidBackground` does NOT use a Flutter `CustomPainter`

---

## 🏃 TASK 0 — MANDATORY BASELINE (Run Before All Other Tasks)

```
1. analyze_files({ "path": "lib/", "options": ["--fatal-infos", "--fatal-warnings"] })
   → Save full output. This is your ground truth.

2. run_tests({})
   → Save: total, passed, failed, skipped counts.

3. dart_format({ "paths": ["lib/"], "setExitIfChanged": true })
   → List every file that would be reformatted.
```

Every finding in Tasks 1–9 must reference data from these three outputs.
Do not re-run analyze_files per-file — the project-wide run already covers everything.

---

## 🔎 TASK 1 — Claim Verification (All 34 Claims)

For each numbered claim above:

1. Use `resolve_symbol` to verify the class/method/annotation exists
2. Cross-reference with `analyze_files` output for errors on that symbol
3. If you need to confirm logic (not just existence), read the file content

**Output format for each claim:**

```
[N] Claim text
Status: ✅ VERIFIED | ⚠️ PARTIAL | ❌ FALSE | 🚧 STUB
Tool used: resolve_symbol("...") / analyze_files output line X / file read
Evidence: exact function name, file path, or "symbol not found"
```

**Specific symbol checks to run:**

```dart
resolve_symbol("ConcatenatingAudioSource.move")
resolve_symbol("BaseAudioHandler")
resolve_symbol("AudioHandler")
resolve_symbol("Isolate.run")
resolve_symbol("riverpod")         // verify @riverpod annotation
resolve_symbol("Song")             // inspect all fields
resolve_symbol("PlayEvents")       // Drift table
resolve_symbol("SongPairs")        // Drift table
resolve_symbol("SongMetadata")     // Drift table
resolve_symbol("FluidBackground")  // verify shader, not painter
```

---

## 💀 TASK 2 — Dead Code, Stubs & Disconnected Services

Use `analyze_files` unused-import warnings + manual call-chain tracing.

### Services to trace (find callers or declare dead):

| Service | Methods to resolve | Look for callers in |
|---|---|---|
| `bpm_analyzer_service.dart` | All public methods | providers/, screens/ |
| `replay_gain_service.dart` | All public methods | audio_handler.dart, providers/ |
| `transcoding_service.dart` | All public methods | subsonic_service.dart, providers/ |
| `cache_settings_service.dart` | All public methods | providers/, services/ |
| `playlist_cache_service.dart` | All public methods | library_provider.dart |
| `search_history_service.dart` | All public methods | search_provider.dart, search_screen.dart |

### Screens to verify have real data sources:

| Screen | Expected data source | Is it actually called? |
|---|---|---|
| `made_for_you_screen.dart` | `recommendation_service.dart` | Trace or declare dead |
| `new_releases_screen.dart` | Subsonic API endpoint | Which endpoint? Hardcoded? |
| `offline_screen.dart` | `offline_service.dart` state | Subscribed or local state? |
| `replay_screen.dart` | `replay_provider.dart` | Full pipeline connected? |

### Stub patterns to find (search every file):

- `throw UnimplementedError()`
- `// TODO` / `// FIXME` / `// HACK`
- Empty async bodies: `Future<void> foo() async {}`
- `return;` as only statement in a non-trivial method

---

## 🗄️ TASK 3 — Data Integrity & Database Risks

Read all files in `lib/database/` and `lib/services/listening_event_collector.dart`.

Answer each question with a YES/NO and evidence:

1. **Missing indexes:** Does any Drift table lack an index on a column used in a
   `WHERE` clause? Check PlayEvents (queried by songId, timestamp), SongPairs
   (queried by songA/songB).

2. **Transaction gaps:** Are multi-step writes (insert PlayEvent + upsert SongMetadata
   + insert SongPair) wrapped in a single Drift `transaction(())`? A crash between
   steps = orphaned data.

3. **Single point of failure:** Do the 2.0s and 5.0s duration thresholds exist ONLY
   in `listening_event_collector.dart`? If yes, bypassing the collector lets junk
   reach the DB — is there any DB-layer guard?

4. **Upsert risk:** Does `SongMetadata` upsert on every "Song Started" event?
   Could rapid skip-storms (next/next/next) cause write contention or lock errors?

5. **Purge logic:** The docs claim a purge utility strips events where
   `duration < 2s AND skipBefore50 == true`. Does this code exist? Is it
   ever called automatically or only manually?

---

## 🔐 TASK 4 — Security Audit

Read these files fully. Search for every pattern listed:

**Files to inspect:**
- `lib/services/subsonic_service.dart`
- `lib/services/replay_upload_service.dart`
- `lib/core/constants.dart`
- `lib/core/app_constants.dart`
- `lib/core/hive_boxes.dart`
- `lib/main.dart`

**Patterns to find (each is a finding if present):**

```
Hardcoded strings: "casaos", "password", "secret", "token", "api_key", "bearer"
Static MD5 salt: any MD5 call where the salt is a string literal, not Random()
WebDAV credentials: any URL string containing username:password@
Hive encryption: are any boxes opened WITHOUT an encryptionKey?
HTTP fallback: does SubsonicService allow http:// URLs, not just https://?
URL injection: is the server URL user-input sanitized before being used in API calls?
Token storage: are auth tokens written to a plaintext Hive box or SharedPreferences?
```

**Severity classification:**

- CRITICAL: exploitable without physical device access
- HIGH: exploitable with device access or by malicious server
- MEDIUM: privacy risk or data exposure
- LOW: best-practice violation, no immediate exploit

---

## ⚡ TASK 5 — Performance Risk Analysis

For each item, read the relevant file and answer concretely:

1. **`palette_cache.dart`** — Does it implement a maximum size cap or LRU eviction?
   A 10,000-album library with no eviction = unbounded RAM growth.
   If no cap: estimate memory footprint (average palette = ~5 colors × 4 bytes × 10,000 albums).

2. **`library_provider.dart`** — Does it paginate Subsonic API responses?
   Run `resolve_symbol` on the library fetch method. Look for `offset`, `count`,
   or `limit` parameters in the Subsonic API call. Loading 50,000 songs at once
   is an OOM risk on low-end devices.

3. **`fluid_background.dart`** — Does the `AnimationController` call `dispose()`
   in the widget's `dispose()` method? A leaked controller keeps the shader
   running on every frame after screen exit.

4. **`FluidBackground` rebuilds** — Is the widget wrapped in `RepaintBoundary`?
   Without it, any parent rebuild triggers full shader re-execution.

5. **Scroll listeners** — Search all screens for `setState` or `ref.invalidate`
   called inside a scroll listener or inside a `build()` method directly.

6. **Image caching** — Does `album_card.dart` or any widget use unbounded image
   caching? Is there a cache size limit configured?

---

## 🚨 TASK 6 — Error Handling Coverage

### Network layer (`subsonic_service.dart`):

Map every outgoing call. For each one, confirm it has a `catch` block that:
a) Catches the specific exception type (DioException, SocketException, etc.)
b) Wraps it in a typed `AppException` from `core/app_exception.dart`
c) Does NOT swallow it silently

Any call missing a or b or c = finding.

### Audio stream errors (`audio_handler.dart`):

Find the `onError` handler on the audio source stream. Determine:
- Does it retry on network drop? (If yes, how many times? With backoff?)
- Does it surface the error to `PlayerProvider` for UI display?
- Or does it silently stall?

### Global error boundary:

Check `main.dart` for:
- A `ProviderObserver` that catches unhandled async provider errors
- A `FlutterError.onError` handler
- A `PlatformDispatcher.instance.onError` handler

### Unawaited futures:

The `analyze_files` output will flag `unawaited_futures` lint violations.
List every occurrence — these are silent failure points in services and providers.

---

## 🔗 TASK 7 — Feature Pipeline Verification

For each feature, trace the FULL data pipeline using `resolve_symbol` and file reads.
A feature is only ✅ CONNECTED if you can trace every link in the chain.
Files existing ≠ features connected.

| Feature | Expected Full Pipeline |
|---|---|
| BPM Analysis | `bpm_analyzer_service` → computed → provider exposes → screen displays |
| Recommendations | `SongPairs` DB query → `recommendation_service` → `made_for_you_screen` |
| Replay | `listening_event_collector` → `replay_upload_service` → WebDAV → `replay_provider` → `replay_screen` |
| Offline Playback | `offline_service` download → local file → `audio_handler` local source → `offline_screen` reflects state |
| New Releases | Subsonic endpoint → response parsing → `new_releases_screen` (what endpoint?) |
| ReplayGain | `replay_gain_service` computes gain → `audio_handler` applies volume normalization |
| Transcoding | `transcoding_service` setting → `subsonic_service` chooses proxied URL → `audio_handler` |
| Playlist Cache | `playlist_cache_service` + DB table → `library_provider` serves cached → screens |
| Search History | `search_history_service` + DB table → `search_provider` → `search_screen` populates |

**Verdict for each:** ✅ CONNECTED | ⚠️ PARTIAL (which link is broken?) | ❌ DEAD END

---

## 🧪 TASK 8 — Test Coverage Report

Run `run_tests({})` for the global baseline.

Then build this table for every file in `lib/services/` and `lib/providers/`:

| File | Test File Exists? | Tests Pass? | Notes |
|---|---|---|---|
| `audio_handler.dart` | ❌ / ✅ | N/A / ✅ / ❌ | |
| `listening_event_collector.dart` | | | |
| `recommendation_service.dart` | | | |
| `subsonic_service.dart` | | | |
| ... (all 11 services + 5 providers) | | | |

Then identify the **5 highest-risk untested paths** — rank by: complexity × consequence of failure:

```
1. Gapless reorder selection-sort loop — wrong index = crash during shuffle
2. Fingerprint deduplication (500ms window) — wrong = inflated play counts
3. Session timeout logic (30-min UUID reset) — wrong = broken listening stats
4. Weighted shuffle k=r^(1/w) formula — wrong = incorrect song priority
5. Drift transaction atomicity — wrong = orphaned DB records on crash
```

---

## 📊 MANDATORY REPORT FORMAT

Your output must follow this exact structure. Start at the header. No preamble.

---

```
# NaviVibe Full Audit Report

**Date:** [today]
**Auditor:** Gemini CLI + Dart MCP Server
**MCP Server Status:** [paste /mcp output]
**analyze_files baseline:** [X errors, Y warnings, Z hints, A infos]
**Test baseline:** [X passed, Y failed, Z skipped]
**dart_format violations:** [N files — list them]

---

## 1. Confirmed MCP Tools Available
[paste /mcp tool list]

---

## 2. Claim Verification (34 Claims)
[34 entries, one per claim, format shown in Task 1]

---

## 3. Critical Findings (Fix Immediately)
[Numbered. Each entry: File · Line (or "unconfirmed") · Problem · Risk · Fix]

---

## 4. Dead Code & Stubs
[Table: File | Symbol | Type (dead/stub/TODO) | Risk]

---

## 5. Security Findings
[Ordered CRITICAL → LOW. File · Pattern found · Risk · Fix]

---

## 6. Data Integrity Risks
[Answers to Task 3 questions 1–5, with file evidence]

---

## 7. Performance Risks
[Answers to Task 5 questions 1–6, with concrete numbers where possible]

---

## 8. Error Handling Gaps
[Table: File · Call · Missing catch/AppException/handler]

---

## 9. Feature Pipeline Verdicts
[Table from Task 7 with verdicts and broken-link explanation]

---

## 10. Test Coverage Report
[Table from Task 8 + top-5 highest-risk untested paths]

---

## 11. Additional Findings
[Real findings not covered above. No filler. No summaries of the docs.]

---

## 12. Priority Fix Order
[Top 15 fixes, ordered by severity × user impact.
Format: [N] File → What to fix → Why it matters]
```

---

## ⛔ ABSOLUTE RULES — VIOLATION = REPORT REJECTED

1. Every factual claim **must name the MCP tool** that verified it.
2. `"The code appears to..."` is **forbidden**. Run the tool. Confirm or deny.
3. Do **not** summarise the architecture docs. Find what is **wrong**.
4. If a tool call fails or a file cannot be read, say so and continue.
5. Do **not** skip any task. If not applicable, state why in one sentence.
6. Do **not** hallucinate line numbers. If unconfirmable, say `"line unconfirmed"`.
7. Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from style findings
   but **not** from logic findings.
8. Read `GEMINI.md` in the project root before starting. Follow every rule it defines.
9. Read `SKILLS.md` in the project root before starting. Apply every skill it defines.
10. If the app is running in debug mode, call `get_runtime_errors({})` before Task 1.
    If not running, state: `"Runtime introspection skipped — app not in debug mode."`
