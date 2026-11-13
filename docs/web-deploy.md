# Deploying the NaviVibe web app at subimusic.me

The Flutter app also builds for the browser. Phones and narrow windows get the
phone UI, desktop browsers the desktop UI (it switches live when the window is
resized). It installs as a PWA on Android Chrome. This page is the runbook for
putting it live on subiserver. Every step here is yours to run: nothing was
changed on the server or in Cloudflare while building this.

## What you end up with

| Hostname | Cloudflare Tunnel ingress | What it is |
|---|---|---|
| `subimusic.me` | `http://127.0.0.1:8090` (new: Caddy) | The web app. Caddy also passes `/rest/*`, `/auth/*`, `/api/*`, `/share/*` to Navidrome, so the Android/Windows apps that use `https://subimusic.me` as their server keep working |
| `navidrome.subimusic.me` | `http://localhost:4533` (new) | Navidrome itself, including its admin UI (keep that private, see below) |
| `shuffle.subimusic.me` | `http://localhost:5500` (unchanged) | Shuffle server: Flow, Smart Shuffle, `/social` (Jam, Collab, People), `/fetch` |
| `session.subimusic.me` | `http://localhost:5501` (unchanged) | Session sync (websocket) |
| tg-fetcher `:5510` | none | Never published |

Today `subimusic.me` points straight at Navidrome (`/etc/cloudflared/config.yml`).
After the switch Navidrome's own web player moves to `navidrome.subimusic.me`;
the Subsonic API stays on both hosts.

## How the web app signs in (why no password is stored)

- Sign-in posts the username and password once to Navidrome's `POST /auth/login`
  and drops the password. Navidrome answers with a JWT plus its own Subsonic
  token and salt.
- Subsonic calls use `u` + `t` + `s` while the tab is open (memory only), and
  `u` + `jwt` after a page reload. The shuffle and session servers get
  `Authorization: Bearer <jwt>`; both already check it against Navidrome.
- The browser stores only the server address, user name and the JWT:
  sessionStorage by default (gone when the tab closes), localStorage when
  "Stay signed in" is ticked. The JWT is renewed every 20 minutes through
  Navidrome's `/api/keepalive` and expires after `ND_SESSIONTIMEOUT` (24 h on
  your server) without use.
- Sign out (Settings > Account) forgets the token and reloads the page.

The one server change this needs is in the shuffle server: it passed the JWT to
Navidrome as `t=`, which Navidrome rejects, so People / friend activity and
Smart Shuffle of a playlist failed for Bearer users. `export/web-server-v1/`
fixes that (it sends `jwt=`).

## 1. Shuffle server patch (`export/web-server-v1`)

Copy the folder to the server and run the installer as `subi` (no sudo):

```bash
scp -r export/web-server-v1 subi@100.99.105.51:~/web-server-v1
```

```bash
ssh subi@100.99.105.51 'bash ~/web-server-v1/install.sh'
```

It tests the patch on a scratch copy, backs up `navivibe/navidrome.py` to
`/opt/shuffle-server/backups/web-server-v1-<time>/`, patches, runs the new
`test_web_auth.py` plus the security and social suites on the live tree (and
puts the old file back if anything fails), then checks the CORS list. Then:

```bash
sudo systemctl restart navivibe
```

The session service is unchanged and needs no restart.

### CORS on the shuffle and session servers

Both read `NAVIVIBE_CORS_ORIGINS` (comma-separated). Unset, the default is
`https://subimusic.me,https://music.subimusic.me,https://shuffle.subimusic.me`,
which already includes the web app. Your `/opt/shuffle-server/.env` does not
set it today, so nothing to do. If you ever set it, keep `https://subimusic.me`
in the list (the installer warns you). The shuffle server allows the
`Authorization`, `Content-Type` and `If-None-Match` headers; the session server
allows `GET` with `Authorization`, which is all the web app sends. Websockets
are not subject to CORS.

## 2. The static server (Caddy on loopback)

The web app is served by its own small Caddy container on `127.0.0.1:8090`,
next to (not inside) the existing `~/subimusic-proxy` Caddy, which you leave
alone. No sudo is needed: it lives in `~/navivibe-web`.

1. Get a build: the GitHub release from `main` carries
   `navivibe-web-<version>+<build>.zip`. Or build locally with
   `flutter build web --release --wasm --no-web-resources-cdn` and use `build/web`.
2. Deploy it (the first run also copies `Caddyfile` and `compose.yaml`):
   ```bash
   bash ~/web-server-v1/deploy-web.sh ~/navivibe-web-1.0.0+123.zip
   ```
3. Check and start Caddy once:
   ```bash
   cd ~/navivibe-web && docker compose run --rm navivibe-web caddy validate --config /etc/caddy/Caddyfile
   ```
   ```bash
   cd ~/navivibe-web && docker compose up -d
   ```
   ```bash
   curl -sI http://127.0.0.1:8090/ | head -5; curl -s 'http://127.0.0.1:8090/rest/ping.view?f=json' | head -c 200; echo
   ```
   The second line should show Navidrome's "missing parameter" JSON: the proxy works.

Later deploys are step 2 only: it switches the `current` symlink and keeps the
last five releases; roll back with `ln -sfn releases/<older> ~/navivibe-web/current`.

What the Caddyfile does (`export/web-server-v1/caddy/Caddyfile`):

- Binds `127.0.0.1` only; TLS is Cloudflare's.
- Same-origin Navidrome for `/rest`, `/auth`, `/api`, `/share` (no CORS needed
  for the web app, and existing app installs keep working).
- Unknown paths fall back to `index.html` (single-page app).
- **Cache headers.** Flutter's output is not content-hashed, so the app code
  (`index.html`, `flutter_bootstrap.js`, `main.dart.js|mjs|wasm`, `sw.js`,
  `manifest.json`, `version.json`) is `Cache-Control: no-cache` (revalidated with
  ETag, a 304 when unchanged). `canvaskit/`, `assets/`, `icons/`, `sqlite3.wasm`,
  `drift_worker.js` are cached for a day.
- **Security headers.** `X-Content-Type-Options`, `Referrer-Policy: same-origin`,
  `X-Frame-Options: DENY`, HSTS, a `Permissions-Policy`, and this CSP:
  ```
  default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline';
  img-src 'self' data: blob: https://navidrome.subimusic.me;
  media-src 'self' blob: https://navidrome.subimusic.me;
  font-src 'self' data: https://fonts.gstatic.com;
  connect-src 'self' https://navidrome.subimusic.me https://shuffle.subimusic.me
              https://session.subimusic.me wss://session.subimusic.me https://fonts.gstatic.com;
  worker-src 'self' blob:; manifest-src 'self'; frame-ancestors 'none'; base-uri 'self';
  object-src 'none'; form-action 'self'
  ```
  `'wasm-unsafe-eval'` is needed for Flutter's wasm and CanvasKit;
  `fonts.gstatic.com` is Flutter's fallback for emoji and scripts Inter lacks.
  The build is made with `--no-web-resources-cdn`, so CanvasKit comes from your
  host, not gstatic. A server address other than these hosts typed into the
  sign-in screen is blocked by this CSP, by design.
- Access logs replace `t`, `s`, `p`, `jwt` and `token` in query strings with
  `REDACTED`.
- No COOP/COEP: the wasm renderer runs single-threaded without them, and
  `require-corp` would block cross-origin covers. Add them only if you want
  multi-threaded rendering and everything is same-origin.

## 3. Cloudflare (dashboard; you do these)

### Tunnel ingress

In `/etc/cloudflared/config.yml` (it is the file the service uses; back it up
first), change the `subimusic.me` entry and add `navidrome.subimusic.me`, above
the final `http_status:404`:

```yaml
  - hostname: subimusic.me
    service: http://127.0.0.1:8090
    originRequest:
      connectTimeout: 60s
      keepAliveTimeout: 120s
      http2Origin: false
  - hostname: navidrome.subimusic.me
    service: http://localhost:4533
    originRequest:
      connectTimeout: 60s
      keepAliveTimeout: 120s
```

Keep `shuffle.`, `session.`, `music.` and `api.` as they are. Then add the DNS
record (once) and restart the tunnel:

```bash
cloudflared tunnel route dns 18d9f431-8f29-4797-8dc9-1ca777e0b137 navidrome.subimusic.me
```

```bash
sudo systemctl restart cloudflared
```

(Or add `navidrome` as a proxied CNAME to `<tunnel-id>.cfargotunnel.com` in the
DNS tab.)

### Navidrome CORS Transform Rule (navidrome.subimusic.me)

The web app talks to Navidrome on its own origin (`subimusic.me/rest`), so it
needs no CORS. Navidrome 0.64 also already answers cross-origin requests itself
(`Access-Control-Allow-Origin: *` on `/rest` and `/auth/login`, preflights
included; checked on the server). Add this rule only if you want to pin the
origin instead of `*`, or if a future Navidrome stops sending the headers:

Rules > Transform Rules > Modify Response Header > Create rule

- Name: `navidrome CORS for the web app`
- When: `(http.host eq "navidrome.subimusic.me" and (starts_with(http.request.uri.path, "/rest/") or starts_with(http.request.uri.path, "/auth/") or starts_with(http.request.uri.path, "/api/keepalive")))`
- Then (Set static):
  - `Access-Control-Allow-Origin` = `https://subimusic.me`
  - `Access-Control-Allow-Headers` = `Authorization, Content-Type, X-ND-Authorization`
  - `Access-Control-Allow-Methods` = `GET, POST, OPTIONS`
  - `Access-Control-Expose-Headers` = `X-ND-Authorization, X-Content-Duration, X-Total-Count`
  - `Access-Control-Max-Age` = `86400`
  - `Vary` = `Origin`

(Navidrome answers `OPTIONS` preflights with 200 itself, so the rule only has to
rewrite headers.)

### Keep admin paths private

- **Navidrome admin UI**: Zero Trust > Access > Applications > Self-hosted,
  domain `navidrome.subimusic.me`, path `app` (and `app/*`), policy "Allow:
  your email". Leave `/rest`, `/auth`, `/api`, `/share` open: the apps and the
  web app need them. The admin UI is not reachable through `subimusic.me` (Caddy
  only passes the API paths).
- **Shuffle server `/admin/*`, `/metrics`**: Security > WAF > Custom rules, Block
  when `http.host eq "shuffle.subimusic.me" and (starts_with(http.request.uri.path, "/admin") or http.request.uri.path eq "/metrics")`.
  Use Tailscale (`100.99.105.51:5500`) for admin work.
- **tg-fetcher**: no hostname, ever.

### Rate limits for a public sign-in page (recommended)

Security > WAF > Rate limiting rules:

- `subimusic.me` and `navidrome.subimusic.me`, path `/auth/login`, POST: 10 per
  minute per IP, block 10 minutes.
- `shuffle.subimusic.me`, path `/social/jam/join`: 6 per minute per IP (the server
  has its own bucket too).

### Caching at the edge

The Caddy headers decide. If you add a Cache Rule, bypass cache for `/rest/*`,
`/auth/*`, `/api/*`, `/share/*` and for `index.html`/`sw.js`; never cache
responses with `Authorization`.

## 4. Check it

1. `https://subimusic.me` on a computer: the desktop UI. Narrow the window below
   ~760 px: the phone UI. On an Android phone: the phone UI.
2. Sign in, play a song, lock the phone: the lock screen shows title, artist,
   cover and play/pause/next (Media Session). On a computer, the keyboard media
   keys work while the tab is open.
3. Jam: start one in the browser, join it from the Android app with the code.
4. Settings > Connection & status: shuffle and session servers reachable.
5. Android Chrome menu > Install app (or "Add to Home screen"): it opens in its
   own black window with the NaviVibe icon.
6. An existing Android/Windows install still signs in with `https://subimusic.me`.

## What the web app does not do

Hidden in the browser build: downloads and the Downloaded list, local music
folders, the download location, CSV export, song recognition ("Identify a
song"), self-update (the page updates on reload), "Sign in another device",
tray, global hotkey, mini-player window, window controls, Windows SMTC (Media
Session replaces it). Sharing shares the link and caption; the PNG card is
app-only. Changing the account is "Sign out" then sign in again.

Background audio on Android Chrome works while the page plays, but a battery
manager can still stop a backgrounded tab; the native app remains the better
Android client. The first play after opening the page needs a tap (browser
autoplay rules), so a session handed over from another device waits for one.
