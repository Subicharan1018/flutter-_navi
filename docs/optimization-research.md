# Optimization research: weight, speed and battery (2026-11)

Scope: Android phone, Android TV, Windows, web and the server path. Goal: a light, fast, low-stress app on weak devices, with no change to audio quality.
Method: static measurement of this checkout plus existing build artefacts, small offline benchmarks in a scratch folder, and primary sources. Nothing under `lib/`, `android/`, `windows/` or `web/` was changed.
No build was run: the PC had 0.49 GB of free RAM (of 15.4 GB) at check time, below the 3 GB bar.

Confidence labels: **sourced** (number from the linked primary source), **measured here** (counted or measured in this repo or its artefacts), **estimated** (reasoned, not measured).

Already done and not re-proposed: Windows idle CPU fix (`Drift` stopped on desktop, Impeller off on Windows, `IdleTrim`), Microduck off by default, fast start and skip debounce, server start copies, play cache, narrow `select` watches on the player.

---

## 1. What the repo looks like today (measured here)

### 1.1 Package weight

| Artefact | Size | Notes |
|---|---|---|
| `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (2026-10-25, CI-style split) | 38.2 MB | Older: still had 1.1 MB of tab `.webp` icons that are gone from `assets/icons/` now |
| `build/app/outputs/flutter-apk/app-release.apk` (2026-11-04) | 50.0 MB | Built for arm64 only, but carries 12.5 MB of armeabi-v7a and x86_64 plugin libraries with no `libflutter.so` for those ABIs (dead weight) |
| Windows `build/windows/x64/runner/Release` (main checkout, 2026-10-11, stale) | 58.4 MB | `flutter_windows.dll` 21.3 MB, `libmpv-2.dll` 15.5 MB, `app.so` 11.0 MB, `sqlite3.dll` 1.5 MB |
| Web build `.dart_tool/flutter_build/f2be3da1…` (2026-11-21) | see 1.3 | wasm + JS fallback |

Breakdown of the 2026-11-04 APK (stored size; native libs are stored uncompressed because `useLegacyPackaging = false`, `android/app/build.gradle.kts:37-41`):

| Component | Size | Share of a 38–43 MB arm64 APK |
|---|---|---|
| `libapp.so` (Dart AOT code) | 13.1 MB (`.text` 8.28 MB, `.rodata` 4.76 MB, no DWARF sections) | ~31% |
| `libflutter.so` (engine) | 11.7 MB | ~27% |
| `libbarhopper_v3.so` (bundled ML Kit barcode, from `mobile_scanner`) | 4.95 MB arm64 (+3.24 v7a, +5.91 x86_64 in the fat APK) | ~12% |
| `assets/mlkit_barcode_models/*.tflite` | 0.88 MB | 2% |
| `libsqlite3.so` | 1.5 MB per ABI | 4% |
| `classes.dex` | 4.55 MB (2.12 MB deflated) | 5% |
| Inter fonts (9 TTF) | 3.76 MB raw, 1.81 MB deflated | 4% |
| `packages/media_kit/assets/web/hls1.4.10.js` | 0.37 MB (0.11 MB deflated) | unused on Android |
| Material and Cupertino icon fonts | 1.6 KB and 1.1 KB | already tree-shaken |

Dependencies: 47 direct (`pubspec.yaml`), 240 packages in `pubspec.lock`. Heaviest native per platform: Android `mobile_scanner` (ML Kit, ~5.8 MB arm64), `sqlite3_flutter_libs` (1.5 MB); Windows `media_kit_libs_windows_audio` (`libmpv-2.dll` 15.5 MB), `sqlite3.dll` 1.5 MB; web `sqlite3.wasm` + `drift_worker.js` (0.46 MB gzip).

### 1.2 Assets, fonts, shaders

- `assets/` 3.8 MB total: fonts 3.7 MB (9 × ~415 KB, `pubspec.yaml` fonts block), icons 84 KB, images 40 KB, tray 4 KB.
- One shader, `shaders/artwork_field.frag` (4 KB).
- Inter-Regular has 2,937 glyphs. Subsetting it to Latin + Greek + Cyrillic + punctuation, keeping `kern liga calt tnum ccmp locl mark mkmk`, gives 204 KB (from 411 KB, −50%); Latin only gives 149 KB (−64%). Measured with `fontTools.subset` in the scratch folder. The app uses 5 weights (`w400` 16 uses, `w500` 22, `w600` 92, `w700` 40, `w800` 10) and `InterDisplay` for text of 20 pt and up (`lib/core/theme.dart:131-132`).

### 1.3 Web

- Build: `flutter build web --release --wasm --no-web-resources-cdn` (`.github/workflows/release.yml:271-273`). Renderer is skwasm in Chromium 137+, dart2js + CanvasKit elsewhere.
- Deferred imports: 0 (`grep "deferred as" lib`).
- Service worker `web/sw.js`: app shell network-first, engine and assets cache-first per build. Fine.
- Server (`tool/web/server/Caddyfile:31`): `encode zstd gzip` on the fly; no precompressed Brotli; no `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers, so skwasm cannot use its render worker thread.
- Sizes (raw / gzip -9 / brotli -q11):

| File | Raw | gzip | Brotli |
|---|---|---|---|
| `main.dart.wasm` | 5.75 MB | 2.10 MB | 1.61 MB |
| `main.dart.js` (fallback) | 6.02 MB | 1.77 MB | 1.34 MB |
| `skwasm.wasm` (engine, Chromium) | 3.59 MB | 1.54 MB | 1.21 MB |
| `canvaskit.wasm` (engine, Safari/Firefox) | 7.28 MB | 2.92 MB | 2.26 MB |
| 9 Inter TTF | 3.76 MB | 1.82 MB | 1.44 MB |
| `sqlite3.wasm` / `drift_worker.js` | 0.73 / 0.37 MB | 0.35 / 0.11 MB | — |

- The web engine waits for every font in `FontManifest.json` before it finishes initialising (`_downloadAssetFonts()` inside `Future.wait` in `initializeEngineServices`, [engine source](https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/lib/web_ui/lib/src/engine/initialization.dart)). So on Chrome the first frame needs about 2.10 + 1.54 + 1.82 = 5.5 MB gzip, and **fonts are a third of it** (measured here).

### 1.4 Startup work before `runApp` (`lib/main.dart`)

Awaited one after another: `HiveBoxes.init()` (`:105`; inside, 6 `openBox` calls plus the secure-storage key for the encrypted auth box, all sequential), `detectTelevision()` (`:106`, a method-channel call), `OfflineService().initialize()` (`:118`), `windowManager` setup on desktop (`:134-150`), `PlayCache.instance.initialize()` (`:169`), `AudioService.init` (`:176`). Then five bootstrap providers are read synchronously (`:212-222`). No timings exist for any of these.

### 1.5 Rebuild scope and render cost

- `ref.watch(`: 538 in `lib/`, 142 with `.select(` on the same line. In the 145 widget files: 394 and 121. Whole `ref.watch(playerProvider)`: 0.
- Whole-state watches that matter:
  - `settingsProvider` watched whole by six network `FutureProvider`s in `lib/providers/library_provider.dart:201, 251, 285, 391, 466, 473` (recently played, playlists, favourites, `allSongsProvider`, recently added, library albums). They only need `serverUrl` and `password`, but `SettingsState` also holds `crossfadeSeconds`, `playbackSpeed`, `motionLevel`, Microduck fields and more (`lib/providers/settings_provider.dart:103-141`). Changing crossfade or speed re-runs all six, and `allSongsProvider` re-reads the whole `song_metadata` table.
  - Download progress: `onReceiveProgress` fires per network chunk (`lib/offline_service.dart:297-301`) and each call copies the whole download map (`lib/providers/download_provider.dart:169-177`). `downloadedSongIdsProvider` builds a new `Set` from every entry on each copy (`library_provider.dart:702-708`). The Downloaded list (and every list while offline) listens to it and reloads its first page from Drift on every change (`library_provider.dart:780-783`); a `Set` is compared by identity, so that is every chunk. `CollectionHero` watches the whole map (`lib/widgets/ui/collection_hero.dart:69`).
- Images: `Image.network` 0. `CachedNetworkImage` 3 sites plus 1 provider, all with `memCacheWidth` or `ResizeImage`. 89 `getCoverArtUrl` calls; `CoverArt` adds a server `size` from `kCoverSteps = [96, 160, 256, 384, 512, 768, 1024]` (`lib/widgets/cover_art.dart:18-29`). With the other fixed sizes (64 palette, 300 notification and car, 600, 900 share, 1080 Now Playing) one cover can exist in up to 12 variants.
- No `CacheManager` config anywhere in `lib/`, so covers use `DefaultCacheManager`: **200 files, 30 days** (`flutter_cache_manager-3.4.2/lib/src/config/_config_io.dart:14-15`). 200 files is a few screens of covers at 12 variants each.
- In-memory image cache: 25 MB / 60 entries on phone and TV (`lib/main.dart:74-75`), 160 MB / 400 on desktop (`:80-82`). Note: `references/performance.md` says "300-entry cap"; the code says 60.
- Costly widgets: `BackdropFilter` 1 (dock glass, `lib/widgets/shell/dock_glass.dart:199-201`, off on TV and behind a raster-time governor), `ImageFiltered` 2 (lyrics, smart context), `ShaderMask` 5, `ClipPath` 1, `Opacity(` 34, `ClipRRect(` 36, `RepaintBoundary(` 33.
- Continuous animations (`.repeat()` at 8 sites, 5 `createTicker`):
  - **`Drift`** (16 s pan) wraps the Weekly Mix cover on Home (`lib/features/weekly_mix/ui/weekly_mix_section.dart:66`). It stops only on desktop or reduced motion (`lib/core/motion.dart:311-315`). On phones and TVs, Home keeps producing frames for as long as it is mounted, the same fault that cost a full CPU core on Windows.
  - `ArtworkField` runs a `Ticker` every vsync while playing on Now Playing, and repaints only at 30 fps (`lib/player/artwork_field.dart:62, 131-153`). A ticker "calls its callback once per animation frame" ([Ticker docs](https://api.flutter.dev/flutter/scheduler/Ticker-class.html)), so a 120 Hz phone still runs 120 frames a second to get 30 repaints.
  - `Shimmer`, `NowPlayingBars`, Jam, record, voice pulse: bounded by visibility, playback or reduced motion. Fine.
- Glass governor: drops the blur when half of 120 frames take over 24 ms to raster (`dock_glass.dart:64-66`). 24 ms is about 41 fps, so a 120 Hz phone (8.3 ms budget) can run at half its rate without tripping it.
- Motion defaults to `MotionLevel.full` on every device, TV and low-RAM included (`settings_provider.dart:152`).

### 1.6 Drift (SQLite)

Indexes (`lib/database/app_database.dart:107-115`): `song_metadata(track_name, artist_name)`, `song_metadata(artist_name)`, `play_events(ts_start)`, `play_events(song_id)`, `local_songs(folder_id)`, `local_songs(server_id)`.
Library paging sorts by `created_at`, `play_count` or `duration_sec` with `LIMIT 50 OFFSET n` (`library_provider.dart:852-862, 919-931`), and none of these has an index. Python `sqlite3` on 20,000 rows: **4.7 ms per page without an index, 0.15 ms with** (`created_at`); `track_name` 5.2 → 0.14 ms (measured here on the dev PC; a weak phone is slower). Drift runs on a background isolate, so this is latency, not jank. `LIKE '%q%'` search cannot use an index either way.
Full-table reads: `library_provider.dart:170`, `listening_event_collector.dart:368`, `local_library_service.dart:197`.

### 1.7 Timers, sockets and background behaviour

| What | Interval | Stops in background? | Where |
|---|---|---|---|
| Position push | 7 s | only while playing | `lib/providers/player_provider.dart:863` |
| Jam invite poll | 45 s | no (only needs social on) | `lib/services/notification_triggers.dart:41, 155` |
| Collab and blend invitation poll | 10 min | no | `notification_triggers.dart:38, 159` |
| People poll | 60 s (20 s while viewed) | no when friend alerts are on | `lib/features/social/logic/people_providers.dart:163-164, 204` |
| Session-sync WebSocket ping | 25 s | no (reconnect only on resume) | `lib/services/session_sync_service.dart:838`, `lib/providers/session_sync_provider.dart:119` |
| Auto-download pass | 10 min | no (only when enabled) | `lib/features/auto_download/logic/auto_download_providers.dart:210` |
| Web session refresh | 1 min | web only | `lib/core/web_session.dart:82, 306` |
| Jam tick, remote view, sleep timer, fetch polls | 0.5–5 s | only while those screens or jobs run | various |

On Android the media foreground service keeps Dart running while music plays, so these timers keep firing with the screen off.

### 1.8 Android build config

- `android/app/build.gradle.kts`: no `isMinifyEnabled`, so Flutter's default applies (R8 is on for release, [docs.flutter.dev](https://docs.flutter.dev/deployment/android)). No ABI filter, no baseline-profile module. AGP already packs library baseline profiles into `.dm` files (`build/app/outputs/apk/release/baselineProfiles/`).
- `AndroidManifest.xml`: `extractNativeLibs="false"` (`:23`), one `AudioService` with `foregroundServiceType="mediaPlayback"` (`:123`), three widget receivers, a car artwork provider. No `largeHeap`.
- CI ships `--split-per-abi` APKs plus a universal APK on `main` (`release.yml:169, 180`). The APK is sideloaded with a self-updater, not installed from Play.

---

## 2. Techniques by platform, with outside evidence

### 2.1 Android phone

| Technique | Expected gain | Source | Confidence |
|---|---|---|---|
| Stop continuous animations that are not being watched | Each running ticker forces a frame every vsync; Flutter's frame budget is 16 ms at 60 Hz and "under 8ms" at 120 Hz | [Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html), [best practices](https://docs.flutter.dev/perf/best-practices) | sourced (mechanism); gain here estimated |
| Narrow rebuilds (`select`), localised `setState` | "When `setState()` is called… all descendent widgets rebuild" | [best practices](https://docs.flutter.dev/perf/best-practices) | sourced, no % |
| Avoid `saveLayer` (`ShaderMask`, `ColorFilter`, `Opacity`), clip only when needed | `saveLayer` "allocates an offscreen buffer… might trigger a render target switch" | [best practices](https://docs.flutter.dev/perf/best-practices) | sourced, no % |
| Batch or drop background network polls | Radio stays at full power for the transfer + ~5 s tail, then 12 s in low power; one bundled transfer per minute keeps it high ~20 s/min | [Optimize network access](https://developer.android.com/training/connectivity/network-access-optimization) | sourced (illustrative, carrier-dependent) |
| Unbundled ML Kit for `mobile_scanner` | Bundled adds "approximately 3 to 10 MB"; unbundled "around 600KB", model fetched by Play services | [mobile_scanner](https://pub.dev/packages/mobile_scanner) | sourced; 5.8 MB here measured |
| Split per ABI / app bundle | Split APKs avoid "native binaries that aren't applicable" | [Flutter Android deploy](https://docs.flutter.dev/deployment/android) | sourced, no %; already done in CI |
| R8 shrinking | On by default for release | [Flutter Android deploy](https://docs.flutter.dev/deployment/android) | sourced; already on |
| `--split-debug-info` | "can dramatically reduce code size" | [App size](https://docs.flutter.dev/perf/app-size) | sourced, **no number found**; `libapp.so` here has no DWARF already |
| Baseline profiles | ~30% faster code execution from first launch, but only for Java/Kotlin (Dart is already AOT); sideloaded installs may not get them until background dexopt | [Baseline Profiles](https://developer.android.com/topic/performance/baselineprofiles/overview) | sourced; low value here |
| Measure startup with `am start -W` (TTID) | Method only | [App startup time](https://developer.android.com/topic/performance/vitals/launch-time) | sourced |
| Impeller (Vulkan on API 29+, falls back to OpenGL ES) | No published per-device numbers found | [Impeller](https://docs.flutter.dev/perf/impeller) | no data found |

### 2.2 Android TV

| Technique | Expected gain | Source | Confidence |
|---|---|---|---|
| Stay inside the low-RAM budget | 1 GB TV: total (anon + swap + graphics + file) must not exceed 280 MB; keep anon + graphics ≤ 200 MB; graphics 30–40 MB | [TV memory](https://developer.android.com/training/tv/playback/memory) | sourced |
| Never decode images above UI resolution | 1 GB TVs render UI at 720p, 1.5 GB at 1080p | same | sourced |
| Avoid intermediate renders (offscreen layers) | Listed as a graphics-memory cost | same | sourced, no % |
| No blocking network calls at startup | Startup memory and time | same | sourced, no % |
| Reduce motion by default on `isLowRamDevice()` | Fewer frames, fewer offscreen layers | same + 2.1 | estimated |
| GPU path | Many TV boxes are below API 29 or lack good Vulkan, so they run the OpenGL ES fallback ([Impeller](https://docs.flutter.dev/perf/impeller)); shader and blur cost there is unmeasured | — | no data found |

### 2.3 Windows

| Technique | Expected gain | Source | Confidence |
|---|---|---|---|
| EcoQoS (efficiency mode) while hidden **and paused** | "up to a 90% reduction in CPU power consumption" in an initial assessment, recent mobile chips only | [Introducing EcoQoS](https://devblogs.microsoft.com/sustainable-software/introducing-ecoqos/), [SetProcessInformation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation) | sourced; must never apply while playing (mpv's audio thread is in-process) |
| Smaller mpv demuxer buffer | `just_audio_media_kit` default `bufferSize` is 32 MB per player (`just_audio_media_kit-2.1.0/lib/just_audio_media_kit.dart:20`), not overridden (`lib/main.dart:129`) | package source | measured here (setting); RAM effect estimated |
| `--analyze-size` for Windows | Method only | [App size](https://docs.flutter.dev/perf/app-size) | sourced |

### 2.4 Web

| Technique | Expected gain | Source | Confidence |
|---|---|---|---|
| Wasm (skwasm) instead of JS | Frame time 34.5 → 17.4 ms, build 29.3 → 11.4 ms, bundle "no more than 5% larger compressed"; M4 Pro, Chrome, 200 animated nodes | [Flutter blog](https://flutter.dev/blog/try-flutter-web-with-webassembly-week) | sourced; already done |
| COOP + COEP headers (multi-threaded skwasm) | Wasm "can use multiple threads to render… with less jank"; no isolated number | [Wasm docs](https://docs.flutter.dev/platform-integration/web/wasm) | sourced, no number |
| Precompressed Brotli | Here: wasm −23%, JS −24%, fonts −21% vs gzip -9 | `brotli -q 11` on artefacts; JS typically 9–30% ([summary](https://en.wikipedia.org/wiki/Brotli)) | measured here |
| Subset or trim the bundled fonts | Fonts are awaited before first frame ([engine](https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/lib/web_ui/lib/src/engine/initialization.dart)); −50% per file (Latin, Greek, Cyrillic) | fontTools here | measured here |
| Deferred imports for rare screens (Replay, year story, recognise, Exportify import, charts) | No number found for Flutter web | — | no data found |
| Keep `--no-strip-wasm` off | Not stripping costs "approximate 47% increase" in wasm size | [Wasm docs](https://docs.flutter.dev/platform-integration/web/wasm) | sourced; already off |

### 2.5 Server path (Navidrome, reverse proxy)

| Technique | Expected gain | Source | Confidence |
|---|---|---|---|
| JSON compression | Navidrome itself gzips JSON and XML at level 5 (`compressMiddleware`, [server/middlewares.go](https://raw.githubusercontent.com/navidrome/navidrome/master/server/middlewares.go)); Dart's `HttpClient` asks for gzip by default. A synthetic 500-song `search3` page: 603 KB → 92 KB (−85%) | source + scratch benchmark | already in place; measured here |
| Larger image cache, fewer cover sizes | `ImageCacheSize` default 100 MB, `EnableArtworkPrecache` true, `CoverArtQuality` 75 ([options](https://www.navidrome.org/docs/usage/configuration/options/)). Up to 12 sizes per cover multiply resize work and cache misses | docs + 1.5 | sourced (defaults); effect estimated |
| Larger transcoding cache | `TranscodingCacheSize` default 100 MB; `Transcoding.EnableCancellation` default false | [options](https://www.navidrome.org/docs/usage/configuration/options/) | sourced; matters only for transcoded or fast-start streams |
| HTTP/2 and keep-alive | Caddy serves HTTP/2 to browsers; the Dart IO client speaks HTTP/1.1 with a pooled keep-alive (retry already added, `docs/performance-2026-11.md`) | — | no data found for gain |

---

## 3. Ranked table

Priority P1 = do first (cheap, clear win), P4 = not worth it now. Effort S < 1 day, M 1–3 days, L more. "Exists" marks what is already in place.

| # | Technique | Platform | Evidence / number | What the repo does now | Effort | Audio-quality risk | Priority |
|---|---|---|---|---|---|---|---|
| 1 | Stop `Drift` on phone and TV when not visible (or make it a still on low-RAM and TV) | Android, TV | Same 16 s loop cost a full core on Windows (measured earlier); a ticker forces every vsync | Runs whenever Home is mounted; stops on desktop only (`lib/core/motion.dart:311-315`, used at `weekly_mix_section.dart:66`) | S | none | P1 |
| 2 | Throttle download progress (e.g. ≥1% or 250 ms) and compare sets by content | Android, Windows | One state copy, one `Set` rebuild and, on the Downloaded list, one Drift page reload per network chunk | `download_provider.dart:169-177`, `library_provider.dart:702-708, 780-783`, `collection_hero.dart:69` | S | none | P1 |
| 3 | Watch only `serverUrl`/`password` in library providers | all | Changing crossfade or speed refetches 6 providers and re-reads all of `song_metadata` | `library_provider.dart:201, 251, 285, 391, 466, 473` | S | none | P1 |
| 4 | Own cover `CacheManager` (e.g. 2,000+ files) and fewer size steps (e.g. 128/256/512/1024) | all native | Default cap is 200 files; up to 12 variants per cover | No config; `cover_art.dart:18` has 7 steps | S | none | P1 |
| 5 | Gate social polls on foreground or a live Jam | Android | Each wake ≈ 5 s full power + 12 s low power on cellular; 45 s Jam poll ≈ up to ~38% radio-elevated time (estimate from sourced timings) | `notification_triggers.dart:155-162`, `people_providers.dart:204` run in background | S | none | P1 |
| 6 | Subset Inter (Latin, Greek, Cyrillic, needed features) | web, all | −50% per file: 3.76 → ~1.9 MB; on web ~0.9 MB less before first frame (fonts are ~1/3 of startup bytes) | 9 full TTF files, `pubspec.yaml` fonts block | M | none | P1 (web), P2 (others) |
| 7 | Precompress web assets with Brotli (`file_server { precompressed br gzip }`) | web | wasm 2.10 → 1.61 MB, JS 1.77 → 1.34 MB, fonts 1.82 → 1.44 MB | `encode zstd gzip` only (`Caddyfile:31`) | S | none | P2 |
| 8 | `ArtworkField`: drive at 30 fps by `Timer`, not a per-vsync `Ticker` | Android, TV | 120 → 30 frames/s while Now Playing is open and playing (estimated 4× fewer frames) | `artwork_field.dart:62, 146-153` | S | none | P2 |
| 9 | Index `created_at`, `play_count`, `duration_sec` | all | 4.7 → 0.15 ms per page on 20k rows (PC) | Not in `_ensureIndexes` (`app_database.dart:107-115`) | S | none | P2 |
| 10 | Glass governor budget from the display rate (e.g. 1.5 × frame interval) | Android | 24 ms lets a 120 Hz phone run at ~41 fps with blur on | `dock_glass.dart:64-66` | S | none | P2 |
| 11 | Reduced motion and smaller image cache by default on `isLowRamDevice()` / TV | TV, weak phones | 1 GB TV: 280 MB total, graphics 30–40 MB | Motion full by default (`settings_provider.dart:152`); glass already off on TV (`dock_glass.dart:108`) | S | none | P2 |
| 12 | Unbundled ML Kit (`dev.steenbakker.mobile_scanner.useUnbundled=true`) | Android, TV | −5.8 MB arm64 APK (4.95 MB lib + 0.88 MB models), +~0.6 MB | Bundled | S | none (needs Play services; Huawei-type phones lose the scanner) | P2 |
| 13 | COOP/COEP (`same-origin` + `credentialless`) for multi-threaded skwasm | web | Docs: less jank, no number | Not set (`Caddyfile`); must check covers and audio from `navidrome.subimusic.me` still load | M | none if media still loads | P2 |
| 14 | Parallelise independent startup awaits (Hive boxes, TV check, offline init, play cache) | all | No number; measure with `am start -W` | Sequential, `main.dart:105-201` | M | none | P2 (measure first) |
| 15 | Server: `ImageCacheSize` 500 MB–1 GB; `TranscodingCacheSize` up if fast start transcodes | server | Defaults 100 MB each | Unknown (server config not in repo) | S | none | P2 |
| 16 | Deferred imports for rare web screens | web | No data found | 0 deferred imports | M–L | none | P3 |
| 17 | `LazyBox` for large Hive boxes (`shuffle_cache_v2`, `play_outbox_v1`) | all | No data found; box files unmeasured | Normal boxes, opened before `runApp` | M | none | P3 |
| 18 | Smaller mpv buffer (e.g. 8–16 MB) | Windows | Default 32 MB per player | Default | S | none to quality; small rebuffer risk on bad links | P3 (measure RAM first) |
| 19 | EcoQoS while hidden and paused | Windows | Up to 90% CPU power (initial, mobile chips) | `IdleTrim` only | M | must be off while playing | P3 |
| 20 | ABI filter for local arm64-only builds | Android | 12.5 MB dead libs in the 2026-11-04 APK | CI is fine (`release.yml:169`) | S | none | P3 |
| 21 | `--split-debug-info` / `--obfuscate` | Android, Windows | No number found; `libapp.so` already has no DWARF | Not used | S | none | P4 |
| 22 | Own baseline profile module | Android | ~30% for Java/Kotlin only; app is sideloaded | Library profiles already packed | M | none | P4 |
| — | Exists: wasm build, split-per-abi, R8, `extractNativeLibs=false`, decode at display size, server-side cover sizing, 64 px palette decode on an isolate, Navidrome gzip, image cache tuned per platform, `NowPlayingBars` and Microduck tickers gated, `IdleTrim`, no whole `playerProvider` watch, glass governor, 6 h library sync cap | — | — | — | — | — | done |

---

## 4. What I could not verify

- No frame, CPU, memory or startup numbers from a device: free RAM was 0.49 GB, so no build, and the phone was not driven. Every "frames per second" gain above is a mechanism, not a measurement.
- Whether `Drift` keeps ticking when Home is covered by another route or tab (`TickerMode` from the shell should mute inactive tabs; a pushed route over Home may not).
- Real size of `libapp.so` with `--split-debug-info` and `--obfuscate`, and a current Windows release size (the only Windows build is from 2026-10-11).
- Hive box sizes on a real install, and how long each startup await takes.
- How often `onReceiveProgress` fires on the phone (chunk size depends on the socket); the per-chunk cost is from code reading.
- Whether COEP `credentialless` breaks cover or audio loading from the separate Navidrome host in each browser.
- The live Navidrome `ImageCacheSize`, `TranscodingCacheSize` and proxy settings on the server.
- Impeller Vulkan versus OpenGL ES cost on typical TV SoCs: no published numbers found.

## 5. Five experiments on the OnePlus (before / after)

Package `com.navivibe.navivibe`. Use a release or profile build; run each 3 times and take the median.

1. **Idle frames on Home (item 1).** Open Home with Weekly Mix visible, do not touch the screen, then sample per-thread CPU for 10 s:
   ```
   adb shell "top -H -b -d 1 -n 10 -p $(pidof com.navivibe.navivibe)" | findstr /R "1.ui 1.raster"
   ```
   Before the fix expect steady CPU on `1.ui` and `1.raster`; after, near 0%. For a frame count, `adb shell dumpsys SurfaceFlinger --timestats -enable -clear`, wait 10 s, then `adb shell dumpsys SurfaceFlinger --timestats -dump` and read `totalFrames` for the NaviVibe layer.
2. **Cold start (item 14, and fonts in item 6).**
   ```
   adb shell am force-stop com.navivibe.navivibe
   adb shell am start -S -W -n com.navivibe.navivibe/.MainActivity
   ```
   Record `TotalTime` (TTID) ten times. Add `Timeline.startSync`/`finishSync` around each `await` in `main()` in a profile build to see which step dominates.
3. **Memory against the TV budget (items 4, 11).** Scroll the 1,000-song library top to bottom twice, then:
   ```
   adb shell dumpsys meminfo com.navivibe.navivibe
   ```
   Note `TOTAL PSS`, `Native Heap` and `Graphics`. Compare with 280 MB total and 30–40 MB graphics for a 1 GB TV.
4. **Background radio and wakeups (item 5).** With social on, music playing and the screen off for 30 minutes:
   ```
   adb shell dumpsys batterystats --reset
   (play 30 min, screen off)
   adb shell dumpsys batterystats com.navivibe.navivibe > before.txt
   ```
   Compare "Mobile radio active", "Wifi" and wakeup counts before and after gating the polls. Run once on mobile data, once on Wi-Fi.
5. **Download churn (item 2).** Open Library → Downloaded, start downloading a 20-song album, and record a trace:
   ```
   adb shell perfetto -o /data/misc/perfetto-traces/dl.pftrace -t 30s sched freq gfx view am
   adb pull /data/misc/perfetto-traces/dl.pftrace
   ```
   Open it in ui.perfetto.dev and compare `1.ui` busy time and the number of `Drift` worker slices before and after throttling. Also time the album download end to end.

---

## Sources

- Flutter: [app size](https://docs.flutter.dev/perf/app-size), [performance best practices](https://docs.flutter.dev/perf/best-practices), [Android deployment](https://docs.flutter.dev/deployment/android), [Wasm](https://docs.flutter.dev/platform-integration/web/wasm), [Impeller](https://docs.flutter.dev/perf/impeller), [Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html), [Wasm week blog](https://flutter.dev/blog/try-flutter-web-with-webassembly-week), [web engine initialisation](https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/lib/web_ui/lib/src/engine/initialization.dart)
- Android: [Baseline Profiles](https://developer.android.com/topic/performance/baselineprofiles/overview), [app startup time](https://developer.android.com/topic/performance/vitals/launch-time), [network access](https://developer.android.com/training/connectivity/network-access-optimization), [TV memory](https://developer.android.com/training/tv/playback/memory)
- Microsoft: [EcoQoS](https://devblogs.microsoft.com/sustainable-software/introducing-ecoqos/), [SetProcessInformation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation)
- Packages and server: [mobile_scanner](https://pub.dev/packages/mobile_scanner), [Navidrome options](https://www.navidrome.org/docs/usage/configuration/options/), [Navidrome middlewares.go](https://raw.githubusercontent.com/navidrome/navidrome/master/server/middlewares.go), [Brotli overview](https://en.wikipedia.org/wiki/Brotli)
