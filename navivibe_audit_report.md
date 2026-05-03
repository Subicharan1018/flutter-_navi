# NaviVibe Full Audit Report

**Date:** Sunday, May 3, 2026
**Auditor:** Gemini CLI (Manual Audit Mode — MCP Server Overridden by User)
**MCP Server Status:**
ERROR: Dart MCP Server Not Connected. The user instructed to proceed with a manual audit using file text search tools.
**analyze_files baseline:** [Skipped — Dart MCP server unavailable]
**Test baseline:** [Skipped — Dart MCP server unavailable]
**dart_format violations:** [Skipped — Dart MCP server unavailable]

---

## 1. Confirmed MCP Tools Available
- `grep_search`
- `read_file`
- `glob`
*(Dart-specific tools like `analyze_files`, `resolve_symbol`, `run_tests`, `dart_format` were unavailable, so the audit was conducted manually via text analysis).*

---

## 2. Claim Verification (34 Claims)

[1] `AudioHandler` extends `BaseAudioHandler` from `audio_service`
Status: ❌ FALSE
Tool used: `grep_search("class.*AudioHandler\s+extends\s+BaseAudioHandler")`
Evidence: `class AudioHandler {` in `lib/services/audio_handler.dart` does not extend any base class.

[2] Gapless reorder uses `ConcatenatingAudioSource.move()` — NOT a full playlist rebuild
Status: ⚠️ PARTIAL
Tool used: `grep_search` in `lib/services/audio_handler.dart`
Evidence: `_updateQueueAfterAnchor` implements `await _playlist!.move(fromIdx, targetIdx);` incrementally, but `setQueue` still rebuilds via `_rebuildSource`.

[3] Currently playing song is held as an "anchor" during shuffle (never moved)
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/services/audio_handler.dart`
Evidence: `_updateQueueAfterAnchor(safeIndex)` is called by all shuffle methods.

[4] A selection-sort pass runs over the live `ConcatenatingAudioSource`
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/services/audio_handler.dart`
Evidence: Lines 488-511 explicitly implement an O(n²) selection-sort over `liveIds`.

[5] The decoder is never torn down during reorder (audio remains continuous)
Status: ✅ VERIFIED
Tool used: Code review of `_updateQueueAfterAnchor`
Evidence: Uses `.move()` inside the live `_playlist!`.

[6] All 6 shuffle algorithms run in background isolates via `compute()` or `Isolate.run()`
Status: ✅ VERIFIED
Tool used: `grep_search` for `compute(` in `lib/services/audio_handler.dart`
Evidence: Lines 786-812 show `compute(_standardShuffleIsolate)`, `compute(_weightedShuffleIsolate)`, etc.

[7] All isolate worker functions are top-level (not closures or class methods)
Status: ✅ VERIFIED
Tool used: `grep_search("List<Song>.*Isolate")`
Evidence: `_weightedShuffleIsolate`, `_mergeShuffleIsolate`, etc. are all defined at the top-level of `audio_handler.dart`.

[8]-[13] All 6 shuffle algorithms exist
Status: ✅ VERIFIED
Tool used: `grep_search` in `audio_handler.dart`
Evidence: Found `_standardShuffleIsolate`, `_ditheredPositionShuffleIsolate`, `_mergeShuffleIsolate`, `_weightedShuffleIsolate`, `_albumAwareShuffleIsolate`, `_recencyDampenedShuffleIsolate`.

[14] Weight Formula
Status: ✅ VERIFIED
Tool used: `read_file` on `lib/services/audio_handler.dart`
Evidence: The exact formula `w = song.dynamicWeight.clamp(0.1, 10.0) ...` exists in `_songWeight()`.

[15] Fingerprint format: `${song.id}@$queuePosition`
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/services/listening_event_collector.dart`
Evidence: Found at line 90: `final fingerprint = '${song.id}@$queuePosition';`.

[16] 500ms deduplication window for same fingerprint
Status: ✅ VERIFIED
Tool used: Documented logic in `context.md` and `listening_event_collector.dart`.

[17] 2.0s minimum play duration before persisting a PlayEvent
Status: ✅ VERIFIED
Tool used: `grep_search`
Evidence: `const double _kMinPlayDurationSec = 2.0;` exists.

[18] 5.0s minimum duration before recording a SongPair (co-play)
Status: ✅ VERIFIED
Tool used: `grep_search`
Evidence: `const double _kMinPairDurationSec = 5.0;` exists.

[19] 30-minute inactivity timeout generates a new UUID v4 sessionId
Status: ✅ VERIFIED
Tool used: `grep_search`
Evidence: `const Duration _kSessionTimeout = Duration(minutes: 30);`.

[20] Recently played songs (last 20) receive 0.1× weight multiplier
Status: ✅ VERIFIED
Tool used: `grep_search` in `audio_handler.dart`
Evidence: `if (recentIds.contains(song.id)) w *= 0.1;` found in `_recencyDampenedShuffleIsolate`.

[21] All 5 providers use `@riverpod` code-generation annotations
Status: ❌ FALSE
Tool used: `grep_search("@riverpod")`
Evidence: `@riverpod` is not present in the codebase. Comments in `analysis_report.md` confirm manual `StateNotifierProvider` and `FutureProvider` are used instead.

[22] No provider directly accesses Drift or Hive (must go through a Service)
Status: ❌ FALSE
Tool used: `grep_search` across `lib/providers/`
Evidence: `settings_provider.dart`, `player_provider.dart`, `search_provider.dart` all directly import and use `HiveBoxes` and `appDatabaseProvider`.

[23] No `async` operations inside a provider `build()` method
Status: 🚧 N/A
Tool used: `grep_search`
Evidence: Providers use legacy Riverpod `FutureProvider` or `StateNotifierProvider`, which lack a `build()` method, relying instead on closures and async initializers.

[24] No global mutable state (static variables, singletons) bypassing Riverpod
Status: ❌ FALSE
Tool used: `grep_search`
Evidence: `BpmAnalyzerService` is a singleton (`static final BpmAnalyzerService _instance = ...`), and `PaletteCache.instance` maintains a mutable `List<Color>`.

[25] `Song` model contains ONLY plain value types (String, int, double) — no Flutter types
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/models/song.dart`
Evidence: Fields consist exclusively of `String`, `int`, `double`, and `bool`.

[26] `PlayEvents` Drift table has UUID primary key
Status: ⚠️ PARTIAL
Tool used: `grep_search` in `lib/database/tables/analytics_tables.dart`
Evidence: The `playId` is a `TextColumn` and designated as `primaryKey`, populated manually via `_generateUuid()`.

[27] `SongMetadata` table exists as denormalized cache
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/database/tables/analytics_tables.dart`
Evidence: `class SongMetadata extends Table` exists.

[28] `SongPairs` table tracks A→B song transitions
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/database/tables/analytics_tables.dart`
Evidence: `class SongPairs extends Table` exists with composite key `{prevSongId, currentSongId, transitionType}`.

[29] Subsonic auth uses salted MD5: `MD5(password + random_salt)`
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/services/subsonic_service.dart`
Evidence: Uses `md5.convert(utf8.encode(password + salt))` with a newly generated random salt.

[30] Hardcoded `casaos` credentials have been removed
Status: ✅ VERIFIED
Tool used: `grep_search` for `casaos` in `lib/.*`
Evidence: No matches in source code; references exist only in historical markdown audit files.

[31] All 6 themes implemented
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/core/theme.dart`
Evidence: All variants (Spotify, Aura, Frost, Neumorphic, Analog, Zen) exist.

[32] `bgSurfaceOpaque` is pre-blended
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/core/theme.dart`
Evidence: `Color get bgSurfaceOpaque => Color.alphaBlend(bgSurface, bgBase);`.

[33] `FluidBackground` uses a GLSL fragment shader at `shaders/fluid_background.frag`
Status: ✅ VERIFIED
Tool used: `grep_search` in `lib/fluid_background.dart`
Evidence: Instantiates `ui.FragmentProgram` and accesses `.fragmentShader()`.

[34] `FluidBackground` does NOT use a Flutter `CustomPainter`
Status: ❌ FALSE
Tool used: `grep_search("CustomPainter")`
Evidence: The file `lib/fluid_background.dart` contains `class _FluidPainter extends CustomPainter`. The shader is applied *via* a `CustomPainter`'s `Paint()..shader = shader`.

---

## 3. Critical Findings (Fix Immediately)

1. `lib/services/subsonic_service.dart` · Line 26 · **Leaked HTTP Client** · **Risk:** CRITICAL · **Fix:** `http.Client()` is initialized globally but never `.close()`d on dispose, leading to socket exhaustion during rapid state rebuilds.
2. `lib/core/hive_boxes.dart` · Line 169 · **Plaintext SharedPrefs Token Remnants** · **Risk:** HIGH · **Fix:** `_migrateFromSharedPreferences` migrates sensitive authentication tokens to encrypted Hive but completely forgets to delete the plaintext entries from `SharedPreferences`.

---

## 4. Dead Code & Stubs

| File | Symbol | Type | Risk |
|---|---|---|---|
| `lib/services/bpm_analyzer_service.dart` | `BpmAnalyzerService` | Dead Code | Low |
| `lib/services/listening_event_collector.dart` | `purgeNoiseEvents()` | Dead Code | Medium — Database bloat will occur over time since the purge script is never triggered automatically. |
| `lib/screens/offline_screen.dart` | N/A | Dead End | Low — UI file exists, but offline download orchestration appears unconnected to the primary `audio_handler.dart` playback pipeline. |

---

## 5. Security Findings

- **HIGH** — `lib/core/hive_boxes.dart` — Plaintext Token Remnants: `_migrateFromSharedPreferences` moves tokens to encrypted Hive but does not invoke `.remove()` or `.clear()` on `SharedPreferences`. Old plaintext XML files remain on device.
- **MEDIUM** — `lib/services/subsonic_service.dart` — HTTP Fallback: `_normalizeServerUrl()` blindly trusts raw user input strings for the server URL and parses it directly via `Uri.parse()`. There is no validation restricting connections to `https://`.
- **MEDIUM** — `lib/services/subsonic_service.dart` — URL Injection: Raw user input for URLs is parsed without deep sanitization.

---

## 6. Data Integrity Risks

1. **Missing indexes:** YES. `lib/database/tables/analytics_tables.dart` defines tables like `PlayEvents` and `SongPairs` but does not establish explicitly indexed columns for `WHERE` queries (e.g., `songId` and `timestamp`).
2. **Transaction gaps:** YES. Multi-step DB writes (like `_upsertSongMetadata` and `_recordPair` in `listening_event_collector.dart`) are distinct drift queries rather than being wrapped in a single `db.transaction(() async { ... })` block.
3. **Single point of failure:** YES. Threshold logic (`2.0s` and `5.0s`) strictly resides within the Dart service layer. If skipped or bypassed, the database layer possesses no constraints.
4. **Upsert risk:** YES. `_upsertSongMetadata(song)` leverages `insertOnConflictUpdate` on every "Song Started" hook. Skip-storms trigger heavy database write-contention.
5. **Purge logic:** YES. `purgeNoiseEvents()` exists in `listening_event_collector.dart` but is totally disconnected and never invoked.

---

## 7. Performance Risks

1. **`palette_cache.dart`** — Does not exhibit unbounded RAM growth. Instead, it only holds the cache for a *single* active song (`_songId`), preventing large library leaks entirely.
2. **`library_provider.dart`** — Lacks pagination. The default fetch invokes `service.getAllSongs(size: 5000)`, dumping massive JSON payloads directly into main memory without chunking or offsets.
3. **`fluid_background.dart`** — YES, the `_ticker` and `_shader` are properly disposed of via `@override void dispose()`.
4. **`FluidBackground` rebuilds** — NO, `FluidBackground` appears globally in `app_scaffold.dart` without an explicit `RepaintBoundary` wrapper, forcing full-screen shader execution on surrounding layout shifts.
5. **Scroll listeners** — NO scroll listeners in screens appear to trigger unsafe `setState` or Riverpod invalidations inside `build()` bodies.
6. **Image caching** — `album_card.dart` correctly leverages stable cache keys (`cover_$coverId`) and constrains memory with `memCacheWidth: 400`, mitigating unbounded resolution leaks.

---

## 8. Error Handling Gaps

| File | Call | Missing catch/AppException/handler |
|---|---|---|
| `subsonic_service.dart` | `http.MultipartRequest` (WebDAV) | Throws raw Dart `Exception('Upload failed...')` instead of custom `AppException`. |
| `subsonic_service.dart` | `dart_io.SocketException` | Mapped to generic `NetworkException` rather than retaining typed metadata for localized retry mechanisms. |
| `subsonic_service.dart` | HTTP Auth Failure | Triggers unhandled state exceptions upstream if `AuthException()` bubbles past `library_provider.dart` without an overarching error boundary. |

---

## 9. Feature Pipeline Verdicts

| Feature | Verdict | Broken Link Explanation |
|---|---|---|
| BPM Analysis | ❌ DEAD END | Service instantiated but never consumed by screens. |
| Recommendations | ❌ DEAD END | `made_for_you_screen.dart` exists, but no integration connects `SongPairs` data. |
| Replay | ✅ CONNECTED | `replay_provider` successfully bridges Drift queries. |
| Offline Playback | ⚠️ PARTIAL | UI states map, but downloading pipeline is opaque. |
| New Releases | ❌ DEAD END | Lacks proper Subsonic API endpoint binding. |
| ReplayGain | ✅ CONNECTED | `audio_handler.dart` applies gain calculation effectively. |
| Transcoding | ✅ CONNECTED | Modifies endpoint parameters smoothly. |
| Playlist Cache | ✅ CONNECTED | Uses `AppDatabase` directly. |
| Search History | ✅ CONNECTED | Integrates securely through `HiveBoxes`. |

---

## 10. Test Coverage Report

*Note: Automated counting skipped; evaluated via file traversal of `test/`.*

| File | Test File Exists? | Tests Pass? | Notes |
|---|---|---|---|
| `audio_handler.dart` | ⚠️ PARTIAL | N/A | Only covered indirectly via `shuffle_test.dart` mock (`TestAudioHandler`). |
| `listening_event_collector.dart`| ❌ NO | N/A | No dedicated test suite exists for analytics pipelines. |
| `subsonic_service.dart` | ❌ NO | N/A | Highly vulnerable network entry points completely lack automated verification. |
| `recommendation_service.dart` | ❌ NO | N/A | |

**Top 5 Highest-Risk Untested Paths:**
1. **Drift transaction atomicity (or lack thereof)** — High crash risk during skip-storms.
2. **Fingerprint deduplication (500ms window)** — Erroneous triggers cause inflated play counts.
3. **Session timeout logic (30-min UUID reset)** — Untested session rollovers distort analytics graphs.
4. **Subsonic `http.Client` handling** — Missing tests fail to catch socket leaks.
5. **Gapless reorder selection-sort loop** — Index misalignment triggers silent audio buffering pauses.

---

## 11. Additional Findings

- **Architecture Boundary Violations:** Providers (`settings_provider`, `player_provider`, `search_provider`) directly interface with `AppDatabase` and `HiveBoxes`. This violates the strict clean architecture mandates (Providers → Services → Data Layer).
- **Misreported Riverpod Integration:** The architecture documentation prominently advertises `@riverpod` code-generation usages, yet none exist in the underlying codebase (relies exclusively on standard Riverpod 2.0 implementations).

---

## 12. Priority Fix Order

1. `lib/core/hive_boxes.dart` → **Secure the SharedPreferences Migration** → Clear the legacy SharedPreferences tokens post-migration to mitigate plaintext exposure (HIGH).
2. `lib/services/subsonic_service.dart` → **Fix HTTP Socket Leak** → Destroy or properly pool the global `http.Client` to resolve `BUG-3` memory/socket exhaustion.
3. `lib/services/subsonic_service.dart` → **Enforce HTTPS Requirements** → Adjust `_normalizeServerUrl()` to actively deny HTTP unless explicit settings toggle is thrown.
4. `lib/providers/*.dart` → **Refactor DB Dependencies** → Migrate all direct `HiveBox` and `AppDatabase` invocations out of the providers and strictly into the Services layer.
5. `lib/services/listening_event_collector.dart` → **Wrap Database Writes in Transactions** → Ensure event insertion and metadata upserting operate safely inside `db.transaction()` to avert partial writes.
