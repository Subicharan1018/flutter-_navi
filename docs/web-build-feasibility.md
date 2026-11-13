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

---

# Part 2: deployment at `subimusic.me`, and the Android browser / PWA question

Planned shape: the web app is the frontend at `subimusic.me`; Navidrome and the other services sit on subdomains of `*.subimusic.me`. Research only; nothing here is implemented.

## 9. DNS, TLS and how traffic gets in

Current state (from `docs/backend/ARCHITECTURE.md` and `SETUP.md`): `subimusic.me` is already on Cloudflare, with a `cloudflared` tunnel to `127.0.0.1`, the shuffle server on `:5500`, session sync on `:5501`, tg-fetcher on loopback `:5510`. The hosts `shuffle.` and `session.` exist already.

| Option | TLS | Fit | Verdict |
|---|---|---|---|
| **Cloudflare Tunnel (keep)** | Cloudflare terminates TLS with its own edge certificates; origin stays plain HTTP on loopback | No inbound ports, home IP hidden, WAF and rate limits in front, websockets work (idle drop about 100 s, handled by the 25 s ping). Free plan caps request bodies at 100 MB (only `/recognize` uploads come close) | **Recommended.** Zero new infrastructure |
| Port-forward 80/443 + Caddy or nginx | Let's Encrypt. A wildcard needs **DNS-01**: Caddy with the Cloudflare DNS plugin, or `certbot --dns-cloudflare`, using an API token scoped to "Zone DNS edit" on this zone only | Exposes the home IP, needs static IP or DDNS, fails under CGNAT or ISP port blocks, you own patching and DDoS exposure | Only if you want to leave Cloudflare |
| Tailscale Funnel | `*.ts.net` certificates only; custom domains are not supported | Public URL would be `<machine>.<tailnet>.ts.net`, not `subimusic.me`; few ports, bandwidth limits, no WAF | Not suitable for the planned domain. Keep Tailscale for private admin access |

DNS provider: stay on Cloudflare. Records are proxied CNAMEs to the tunnel. List hostnames explicitly rather than a `*` wildcard, so an unused name never resolves to something.

| Host | Backs | Public? |
|---|---|---|
| `subimusic.me` | static web build | yes |
| `navidrome.subimusic.me` | Navidrome `:4533` | yes (see section 12) |
| `shuffle.subimusic.me` (existing; an `api.` alias is fine) | shuffle, social, fetch `:5500` | yes, authenticated |
| `session.subimusic.me` (existing) | session sync `:5501` | yes, authenticated |
| tg-fetcher `:5510` | internal | **never**: loopback only, HMAC-signed |

With the tunnel you do **not** need Let's Encrypt DNS-01 at all; it matters only if you stop proxying through Cloudflare.

## 10. Reverse proxy: needed or not

`cloudflared` already routes by hostname through its ingress rules, so a separate proxy is optional. Add one only for the same-origin layout (section 11) or to serve the static build with tuned headers.

| Proxy | Pros | Cons |
|---|---|---|
| **Caddy** | Smallest config, automatic HTTPS and DNS-01 if you leave the tunnel, compression and websockets by default | One more service |
| nginx | Already referenced in the repo's `deploy/nginx/`; mature | Manual certs and headers |
| Traefik | Label-based routing | Heavier; no Docker in the stack today |

The static build can also be served by Cloudflare (Pages or R2) so page loads never touch the home server. Cache hashed assets as immutable; `index.html` and the service worker are no-cache.

## 11. Subdomains versus same origin: CORS, cookies, tokens

| | Subdomains | Same origin (`subimusic.me/rest`, `/shuffle`, `/ws/session` behind one proxy) |
|---|---|---|
| CORS | Every API call is cross-origin. Shuffle: `NAVIVIBE_CORS_ORIGINS=https://subimusic.me`. Session: already `*`. **Navidrome has no CORS setting**: add the headers at the proxy or a Cloudflare Transform Rule, including the `OPTIONS` preflight (`Allow-Headers: Authorization, Content-Type`, `Max-Age: 86400`) | None |
| Preflights | `Authorization` headers force a preflight per origin and path; Subsonic query-string auth does not | None |
| Cookies | `Domain=subimusic.me` cookies reach every subdomain, including any future compromised one. Prefer host-only cookies or bearer tokens | Host-only `HttpOnly; Secure; SameSite=Lax` works |
| SameSite | `subimusic.me` and `navidrome.subimusic.me` are the **same site**, so SameSite does not block these requests; CORS is the separate wall. Cookie-based `fetch` would need `credentials: include`, an exact `Allow-Origin` (not `*`) and `Allow-Credentials: true` | Not an issue |
| Media URLs | `<audio>` and `<img>` load cross-origin without CORS, but carry `u/t/s` in the URL | Same |
| Flexibility | Each service moves on its own; the app already has per-service base URLs | One proxy to maintain; the app needs relative base URLs |

Recommendation: **start with subdomains**, add the Navidrome CORS rule at Cloudflare or Caddy, and use **bearer tokens, not cookies**. Move to same origin only if preflight latency or CORS upkeep becomes a burden.

Token handling in the browser:
- Do not keep the Navidrome password. The session server already accepts a Navidrome JWT (`Bearer` or `?token=`), and `SECURITY.md` says the shuffle server accepts one too. The Subsonic API needs `u`+`t`+`s`, which derive from the password, so the web client must use JWT-based Navidrome calls or a Subsonic API key if the installed version supports it. **Open item: confirm what Navidrome 0.64 offers and design the web token flow before building.**
- Hold the token in memory plus `sessionStorage` or IndexedDB, with short expiry and refresh (the session service already signals refresh with close code 4001).
- Strict CSP: `connect-src` limited to the three API hosts, `media-src` and `img-src` to the Navidrome host. This limits what an XSS can steal.
- WebSocket `?token=` lands in access logs. Redact the query string for `/ws/` at the proxy or Cloudflare, or swap the token for a one-time ticket.

## 12. Exposing the APIs publicly: what stays private

From `docs/backend/SECURITY.md`: every route but `/health`, `/ready`, `/weather`, `/` needs a Navidrome login; per-IP and per-user rate-limit buckets; failed-login lockout; fail2ban bans land at Cloudflare; tg-fetcher requires an HMAC-signed call from the shuffle server; `/admin/*` is limited to named admins; `/fetch/*` writes need an explicit grant.

| Surface | Public? | Notes |
|---|---|---|
| Static web build | Yes | contains no secrets |
| Navidrome `/rest`, `/api`, `/auth` | Yes, hardened | It is the identity provider, so a flaw is total. Keep it patched, no default admin credentials, sharing and public links off if unused, Cloudflare rate rule on `/auth/login` and `/rest/ping` |
| Navidrome admin UI | Prefer private | Reach it over Tailscale, or put Cloudflare Access (SSO) in front of the UI path while leaving `/rest` and `/auth` open for the web client |
| Shuffle user routes | Yes, authenticated | already bucketed per route class |
| `/admin/*` | Block at the edge, allow only Tailscale IPs | defence in depth |
| `/fetch/*` | Public but grant-gated | keep `FETCH_DEFAULT_ACCESS=none`; show download UI only when `/me/capabilities` allows it |
| `/recognize`, `/intent`, `/lyrics/translate` | Public, strict buckets | paid APIs; a web page is easier to script than an app, so consider lower bursts for browser clients |
| `/social/jam/join` | Public, 6 per minute | the friend-invite flow |
| Session sync | Public, authenticated | CORS `*` is acceptable with bearer tokens; replace it with the exact origin if cookies are ever used |
| tg-fetcher `:5510`, Telegram session, `.env` | **Never** | stays on `127.0.0.1`, no tunnel ingress entry |

Edge controls to add for a browser audience:
- Cloudflare rate-limit rules on `/auth/login`, `/rest/ping` and `/social/jam/join`; Turnstile or Bot Fight Mode on the sign-in page (a browser form is far easier to credential-stuff than the app).
- fail2ban: extend the filters to Navidrome failed-login lines and the web origin's 401s; real client IP keeps coming from `CF-Connecting-IP`, trusted only from loopback.
- Optionally check `Origin` on state-changing shuffle routes (browsers always send it, native apps do not).
- **Product decision needed:** friends joining a Jam from a link usually have no Navidrome account, but today a Jam needs a login plus the code. A guest role would need its own restricted-access design.
- Security headers on the static host: CSP, `X-Content-Type-Options`, `Referrer-Policy`, HSTS.

## 13. Android browsers: mobile web and PWA

**Installability.** Needs `manifest.json` (Flutter generates one; set name, `display: standalone`, 192 and 512 icons including a maskable one, `theme_color`, `start_url`), HTTPS and a registered service worker. Chrome on Android then offers install and opens it in its own window. Flutter's generated service worker caches the shell; a small custom one (Workbox) gives control over cover-art caching.

**Audio in the background and lock screen.**
- Chrome on Android generally keeps a playing `<audio>` element alive with the screen off or the tab backgrounded, which is what `just_audio` web uses. A paused or idle page can be frozen or discarded, so queue advance should happen while the element is still playing (preload the next track, avoid silent gaps).
- Media Session API (`navigator.mediaSession`) gives lock-screen and notification controls in Chrome, Edge, Firefox and Samsung Internet on Android: title, artist, artwork, play, pause, next, previous, seek. `audio_service` web wires the basics; verify the seek bar, artwork sizes (96-512 px) and action handlers on a real device.
- An installed PWA behaves better than a tab, but Doze and OEM battery managers (OnePlus included) can still kill a backgrounded renderer. A native foreground service is immune.
- Autoplay: the first play needs a tap, so session handover and resume-on-open cannot start sound alone.
- No equivalents for Android Auto, home-screen widgets, TV, or the quick-settings tile.
- Wake Lock API can keep the screen on for lyrics; it does not help background audio.

**Offline.**
- A service worker plus Cache Storage can hold the shell and cover art. Caching audio is possible (Range requests need custom handling) but quotas are a fraction of free disk, entries can be evicted unless `navigator.storage.persist()` is granted, and nothing is visible in the file system. Fine for a few playlists, not a multi-GB library.
- No Storage Access Framework or folder scanning: Android Chrome lacks the directory picker, so Local Library stays native.
- Background sync is limited; the native resumable download queue has no equal.

**Performance.** 5.3 MB wasm plus fonts and CanvasKit on first load; heavier memory than native on mid-range phones; the custom fragment shader and long lists need profiling. Repeat opens are fast through the service worker.

### Replace or complement the native Android app?

**Complement.** The PWA suits Jam links, iPhone/Mac/Linux users, zero-install trials and desktop browsers. It cannot match native for background reliability, large offline libraries, local files, Android Auto, widgets, TV, or the self-updater.

| Capability | Native Android | PWA on Android Chrome |
|---|---|---|
| Playback with screen off | Reliable (foreground service) | Works, can be killed by battery managers |
| Lock-screen controls | Full | Good via Media Session |
| Offline downloads | Full | Limited, evictable |
| Local files | Yes | No |
| Android Auto, widgets, TV | Yes | No |
| Install | APK | Add to Home screen |
| Updates | Self-updater | Automatic on load |
| Start-up | Fast | Slower first load |

Guide: ship web first for Jam links and non-Android devices; keep native as the primary Android client; revisit replacement only if native upkeep becomes a burden and offline and Auto stop mattering.

## 14. Added effort and risks

| Area | Size |
|---|---|
| Cloudflare hostnames and CORS rules (Navidrome rule, shuffle env) | S |
| Static hosting, cache headers, CSP and security headers | S |
| Web token and auth redesign (JWT or API key instead of stored password; guest Jam access) | M, the biggest open item |
| PWA manifest, icons, custom service worker, Media Session checks on real devices | M |
| Optional audio caching in the service worker | M-L |
| Edge hardening for a public browser audience | S-M |

New risks:
- A public web sign-in page is a credential-stuffing target; the tunnel does not change that.
- Navidrome CORS lives outside Navidrome, so the rule can silently break after infrastructure changes.
- Guest Jam join conflicts with the "everyone has a Navidrome account" model.
- Background audio on Android Chrome depends on the device maker; test on the OnePlus used for native work.

Checks to run before committing to the build: (1) confirm Navidrome 0.64 token options for a browser; (2) test Navidrome behind a CORS rule with a real preflight; (3) boot the wasm build in desktop and Android Chrome and list runtime exceptions from the `dart:io` files; (4) play a 30-minute playlist on Android Chrome with the screen off and watch for dropped queue advances.
