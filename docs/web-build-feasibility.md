# NaviVibe on the web: feasibility

Investigation only. Nothing in `lib/` was changed. Date: 2026-11-14, Flutter stable at the time, branch `claude/web-feasibility-faaaaf`.

## Verdict

**Feasible, medium effort (about 2-3 weeks for a useful web player; Jam-join page alone is days).**
The app compiles for the browser far more easily than expected: the only compile blocker is one Windows-only plugin. The real work is runtime: storage, offline files, the audio source type, and lock-screen/media integration. The backend is already close to web-ready (session sync allows any origin and takes its token in the query string; everything is HTTPS behind Cloudflare).

## 1. What the builds said

| Build | Result |
|---|---|
| `flutter build web` (JS, dart2js) | **Fails**, 21 errors, all from `smtc_windows` |
| `flutter build web --wasm` | **Fails**, same 21 errors |
| Both, with `smtc_windows` stubbed out (temporary, reverted) | **Both pass.** wasm: 5.3 MB `main.dart.wasm`, whole `build/web` 55 MB (CanvasKit fallback + assets + fonts) |

The 21 errors: `smtc_windows-1.1.0` `frb_generated.web.dart` (inline-class feature off), `smtc_windows_base.dart` (8, int/BigInt), `extensions.dart` (5, int/BigInt), plus [lib/services/windows_smtc.dart](../lib/services/windows_smtc.dart) lines 254-258 (5, int/BigInt). The plugin generates BigInt fields on web via flutter_rust_bridge, which the app's int code does not match. A wasm dry run also flags `flutter_rust_bridge` (a transitive of smtc_windows).

Why `dart:io` did not break either build: Flutter's web SDK lets `dart:io` be imported (28 files do) and defers failure to runtime (`UnsupportedError` on `File`, `Directory`, `Platform`, `ProcessInfo`). So a green build does **not** mean it runs. I could not boot the build in a browser here (starting a local web server was not permitted in this session), so every runtime verdict below is from reading the code, not from running it.

Raw logs: JS `web-js.log`, wasm `web-wasm.log` (in the session scratchpad, not committed).

## 2. Blockers

Counts: 363 Dart files; 28 import `dart:io`; 8 call `Platform.isX` directly (the rest already go through `PlatformUtils`, which is `kIsWeb`-guarded); 0 use `dart:ffi`; 8 use `path_provider`.

### Compile blockers (1)
- `smtc_windows` ([lib/services/windows_smtc.dart](../lib/services/windows_smtc.dart), imported by [lib/main.dart:19](../lib/main.dart)). Fix: conditional import; web gets a no-op `SmtcWindowsSink.create() => null`. The controller logic in the same file is pure Dart and can stay.

### Runtime blockers by area

| Area | Files | Problem | Web answer |
|---|---|---|---|
| Audio source | [navi_audio_handler.dart:584-622](../lib/services/navi_audio_handler.dart) | `LockCachingAudioSource` is not supported on web (needs a local HTTP proxy) | Use `AudioSource.uri` on web (already the fallback branch). `ConcatenatingAudioSource`/`setAudioSource` work on just_audio web |
| Desktop audio bridge | [main.dart:99](../lib/main.dart), `just_audio_media_kit`, `media_kit_libs_*` | Guarded by `!kIsWeb` already; only the imports must not break | Works as is (just_audio's web impl is the default) |
| Local DB | [lib/database/app_database.dart](../lib/database/app_database.dart) | `driftDatabase(name:)` from `drift_flutter` | Works on web only with `sqlite3.wasm` + `drift_worker.js` in `web/` and `DriftWebOptions`. Persistence is IndexedDB/OPFS |
| Key-value | [lib/core/hive_boxes.dart](../lib/core/hive_boxes.dart), `hive_ce` | Encryption key lives in `flutter_secure_storage` | `hive_ce` works on web (IndexedDB). `flutter_secure_storage` web uses WebCrypto + localStorage: it is obfuscation, not a vault. Treat the stored password as exposed to any script on the origin |
| Offline downloads | [lib/offline_service.dart](../lib/offline_service.dart), `local_library/*`, `card_capture.dart`, `crash_log.dart`, `listening_event_collector.dart` | `File`, `Directory`, `getApplicationDocumentsDirectory` (8 files use `path_provider`) | **Drop on web** (hide Downloads/Local Library). Or later, Cache API/OPFS |
| Cover/artwork from `file:` | [lib/widgets/cover_art.dart](../lib/widgets/cover_art.dart), [lib/player/artwork.dart](../lib/player/artwork.dart) | `File.fromUri` only for local `file:` URLs | Network branch works. Guard the `file:` branch |
| Self-update | `features/updates/*` | `Platform.isAndroid/isWindows` unguarded at [update_providers.dart:20-24,147](../lib/features/updates/logic/update_providers.dart), [update_service.dart:89,105](../lib/features/updates/logic/update_service.dart) | **Drop on web**; make `updatesSupported` false behind `kIsWeb` first (it would throw) |
| Platform sniffing | [platform_utils.dart](../lib/utils/platform_utils.dart), [player_provider.dart:1141](../lib/providers/player_provider.dart) | Mostly guarded. `ProcessInfo` import in player_provider | Add `isWeb`; make layout choice width-based on web, not OS-based |
| HTTP error type | [subsonic_service.dart:262](../lib/services/subsonic_service.dart) | `dart_io.SocketException` catch | Add a web branch (browser errors surface as `ClientException`/`DioException`) |
| Session sync | [session_sync_service.dart](../lib/services/session_sync_service.dart) | `import 'dart:io'` (WebSocket via `web_socket_channel`) | `web_socket_channel` is web-capable. Header auth is impossible in browsers: use `?token=`, which the server already supports |
| Windows shell | `window_manager`, `tray_manager`, `hotkey_manager`, `smtc_windows`, `windows_startup`, `mini_player` | Desktop-only plugins | **Drop on web**; conditional-import no-ops |
| Linux media | `audio_service_mpris` | Linux-only | Drop |
| Android integrations | `android_integration.dart`, `PlatformUtils` method channel | MethodChannel, TV detection | Drop (already guarded) |

### Plugin-by-plugin (pubspec)

| Package | Web support | Verdict |
|---|---|---|
| just_audio, audio_session | Yes (HTML audio) | works; no gapless guarantees, no cache source |
| audio_service | Yes, via Media Session API (limited, needs the handler to publish metadata) | works with caveats |
| flutter_riverpod, http, dio, crypto, uuid, collection, archive, fl_chart, qr_flutter, marquee, image, cryptography | Pure Dart | works. `dio` uses browser XHR: no custom HTTP adapters |
| web_socket_channel | Yes | works |
| hive_ce / hive_ce_flutter | Yes (IndexedDB) | works |
| shared_preferences | Yes (localStorage) | works |
| drift / drift_flutter | Yes with wasm sqlite + worker files | needs web impl (setup) |
| flutter_secure_storage | Yes, weak | works, weaker security |
| cached_network_image, flutter_cache_manager | cached_network_image works; cache manager is IO-based | works for display; `getSingleFile` calls ([artwork.dart:170](../lib/player/artwork.dart), [share_sheet.dart:104](../lib/features/share/share_sheet.dart)) need web paths |
| connectivity_plus | Yes | works |
| package_info_plus, device_info_plus | Yes | works |
| share_plus | Yes (Web Share API where available; falls back to copy) | works, partial |
| file_picker | Yes (bytes only, no paths) | needs web impl where it reads paths |
| path_provider | **No** | drop/guard (8 files) |
| disk_space_plus, audio_metadata_reader | No / IO-based | drop |
| record | Yes (MediaRecorder) | works if https; see recognize |
| speech_to_text | Yes (Chrome only) | works in Chrome, not Firefox |
| permission_handler | Mostly no-op on web | guard |
| mobile_scanner | Yes (ZXing JS) | works over https, camera prompt |
| smtc_windows, tray_manager, hotkey_manager, window_manager, audio_service_mpris, just_audio_media_kit, media_kit_libs_* | No | drop, conditional import |
| cupertino_icons, flutter_launcher_icons | n/a | fine |

Fragment shader `shaders/artwork_field.frag`: runtime shaders work on web with CanvasKit/Skwasm but not in the HTML renderer. Needs a visual check.

## 3. Per-feature verdict

| Feature | Verdict |
|---|---|
| Sign-in (Subsonic token auth) | Works (CORS needed, see section 4) |
| Home, Library, Search, Playlists, Albums, Artists, Stars | Works (pure HTTP + Riverpod) |
| Streaming playback, queue, seek | Works with `AudioSource.uri` |
| Gapless / transcoding choice | Works, browser decides gapless quality |
| Now Playing, lyrics, translations | Works |
| Smart Shuffle / Flow / Weekly mix / Replay / trending | Works (shuffle server over HTTPS) |
| Jam / Collab / Blend / friend activity (`/social`) | Works. This is the strongest case for a web build |
| Session sync / handover | Works (websocket) |
| Fetch/download-from-Telegram proxy (`/fetch`) | Works (server-side action); local save to device is a browser download or dropped |
| Offline downloads, local library, SAF folders | **Drop** |
| Lock-screen / hardware keys | Partial: Media Session API via audio_service |
| Cast, share cards (PNG) | Needs web impl (Blob download instead of file) |
| Song recognition (mic) | Works on https in browser |
| Voice search | Chrome only |
| QR sign-in of another device | Works (scan) / show (QR) |
| Self-update, tray, hotkeys, mini player, window sizing, SMTC, MPRIS, notifications | **Drop** |
| Widgets / Android Auto / TV | N/A |

## 4. Server side

Facts taken from `docs/backend/*` and the session server source:

- Public path: Cloudflare edge, then a `cloudflared` tunnel, then `:5500` (shuffle, Flask/waitress) and `:5501` (session sync, FastAPI). Hosts `shuffle.subimusic.me`, `session.subimusic.me`. **All HTTPS/WSS already**, so mixed content is only a risk if someone points a web build at a plain `http://` Navidrome (the app lets users type one).
- **Session sync (:5501):** `CORSMiddleware` with `allow_origins=["*"]`, headers `Authorization, Accept`. The websocket takes `?token=` and the source says "a web client" explicitly. No change needed.
- **Shuffle server (:5500):** CORS only for `NAVIVIBE_CORS_ORIGINS` (default: the author's web player), no credentials, limited headers. Add the web app origin to the env var. Browsers send `Authorization` (Basic) which triggers a preflight, so `Authorization` must be an allowed header. Confirm on the server; I did not have access to it.
- **Navidrome (:4533):** not configured for CORS by default (it has no CORS setting). Subsonic `stream.view` for `<audio>` playback does not need CORS (media elements may load cross-origin), but JSON calls (`getAlbumList2`, etc.) via XHR **do**. Also Web Audio visualizers or fetching cover bytes cross-origin need it.
- **Auth in the browser:** the app keeps the Subsonic password to derive `t`/`s` per request ([subsonic_service.dart:125](../lib/services/subsonic_service.dart)), and uses Basic auth/`base64(user:password)` tokens for the shuffle and session servers. In a browser that means the password sits in IndexedDB/localStorage. Mitigation: prefer a Navidrome JWT (the session server already accepts one), short lifetime, and a strict CSP.
- Cover/stream URLs carry `u`, `t`, `s` in the query string. Fine for media elements, but they end up in browser history and access logs.

**Same-origin reverse proxy on the server solves nearly all of it.** Serve the web build and proxy under one host, e.g. `https://app.subimusic.me`:

```
/                -> static build/web   (COOP/COEP only if you want multithreaded skwasm)
/rest/ , /auth/  -> navidrome :4533
/shuffle/        -> :5500
/ws/session, /playback/ -> :5501 (websocket upgrade)
```

Same origin means no CORS, no preflights, one TLS cert, and cookies/JWT can be `HttpOnly` later. The app's base URLs are currently hardcoded ([session_sync_service.dart:437](../lib/services/session_sync_service.dart), the `shuffle.subimusic.me` constant), so the web build needs relative base URLs. Cloudflare's roughly 100 s idle websocket drop is already handled by the 25 s ping in session sync.

## 5. Recommended architecture

1. **Conditional-import layer**, one tiny file pair per capability, with a stub on web: `window_shell`, `tray`, `hotkeys`, `smtc`, `mpris`, `file_store`, `update_service`, `platform_paths`. Pattern: `export 'x_stub.dart' if (dart.library.io) 'x_io.dart';`. Put `PlatformUtils.isWeb` on top and make `isDesktop` mean "wide layout" on web.
2. **Audio:** keep `just_audio` + `audio_service` unchanged; add a web branch in `_sourceFor` (use `AudioSource.uri`) and disable the media_kit bridge. Media Session API comes through `audio_service`; add a thin `package:web` shim only if it falls short.
3. **Storage:** keep Hive CE; use `drift` with the wasm worker (`sqlite3.wasm`, `drift_worker.js` under `web/`); accept `flutter_secure_storage` web limits, or move web tokens to a session-only store.
4. **Downloads/local library:** hidden on web via `capabilities.supportsOffline`.
5. **Layout:** the separate desktop widget tree already exists, so the web uses it above a breakpoint and the phone tree below. This is the biggest reuse win.
6. **Build:** `flutter build web --wasm` with JS fallback (default when wasm is unsupported). Safari/Firefox are fine on the JS path.
7. **Hosting on the server:** nginx or caddy as above, `Cache-Control` immutable on hashed assets, short TTL on `index.html`/`flutter_service_worker.js`, brotli on. Do not rely on Tailscale for friends: they need the public Cloudflare hostname.

## 6. Effort

| Area | Size | Notes |
|---|---|---|
| Conditional imports for Windows shell + smtc + updates | S | ~15 files touched, mechanical |
| Storage (drift wasm, hive, secure storage) | M | one-time setup + test |
| Audio source and media session | S-M | small code; testing across browsers is the cost |
| Hide/replace file features (offline, local library, share cards, crash log, export) | M | many UI entry points |
| Web layout and input (mouse, keyboard, URL routing, deep links for Jam) | M | the app uses imperative `Navigator`; deep-linking `/jam/<code>` needs routing for at least that page |
| Auth and security (JWT instead of password in storage, CSP) | M | |
| Backend/proxy/CORS | S | |
| Visual/shader/perf QA, bundle size | M | 55 MB build dir, mostly fonts + CanvasKit |
| **Overall** | **M-L**, about 2-3 weeks for a full web player; **S-M, days**, for a minimal "join a Jam from a link + play" page | |

## 7. Risks

- **Wasm/dart2js behaviour of 28 `dart:io` files is untested at runtime.** Compiles, may throw on first launch. Add `kIsWeb` guards before anything else.
- **Password in the browser.** The model of keeping the Subsonic password client-side is weak on the web. Needs JWT/tokens before inviting friends.
- **iOS Safari background audio:** playback stops when the tab is backgrounded or locked unless Media Session is wired correctly; not as good as a native app. Expect complaints.
- **Autoplay policy:** the first play must follow a user gesture; session handover and auto-resume on load won't start audio.
- **Navidrome CORS** is not configurable in Navidrome itself; relying on the reverse proxy is the answer.
- **Public exposure:** a web client on a public hostname raises the abuse surface (rate limits already exist per user and IP; the Jam join endpoint has its own bucket).
- **Maintenance:** two UIs' worth of platform branches. The conditional-import layer keeps this contained but every new native feature needs a web stub.
- **Bundle size/first load:** 5.3 MB wasm plus fonts; fine on Wi-Fi, slow on mobile data. Consider deferring the shader and unused fonts.
- **Plugin churn:** `smtc_windows` is the only compile blocker today, but any future plugin without web support will block the build again, so add `flutter build web` to CI.

## 8. Reproducing

```bash
flutter config --enable-web
flutter create --platforms web --project-name navivibe .   # web/ is gitignored here
flutter build web          # fails on smtc_windows
flutter build web --wasm   # fails on smtc_windows
```
Then stub `SmtcWindowsSink` (conditional import) and both pass. No spike was committed.
