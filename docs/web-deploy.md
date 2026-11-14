# Deploying the NaviVibe web app at subimusic.me

The Flutter app also builds for the browser. Phones and narrow windows get the
phone UI, desktop browsers the desktop UI (it switches live when the window is
resized). It installs as a PWA on Android Chrome. It is hosted on subiserver,
next to Navidrome and the NaviVibe services, behind the Cloudflare Tunnel that
already runs there.

Every step on this page is yours to run. Nothing was changed on the server or in
Cloudflare while building this; the server was only read (over Tailscale SSH).

## What you end up with

| Hostname | Tunnel ingress (`/etc/cloudflared/config.yml`) | What it is |
|---|---|---|
| `subimusic.me` | `http://127.0.0.1:8090` (**changed**: was Navidrome) | The web app, served by Caddy in Docker on loopback. Caddy also passes `/rest/*`, `/auth/*`, `/api/*`, `/share/*` to Navidrome, so the Android/Windows apps that use `https://subimusic.me` keep working |
| `navidrome.subimusic.me` | `http://localhost:4533` (**new**) | Navidrome itself, including its admin UI (keep that private, below) |
| `shuffle.subimusic.me` | `http://localhost:5500` (unchanged) | Shuffle server: Flow, Smart Shuffle, `/social` (Jam, Collab, People), `/fetch` |
| `session.subimusic.me` | `http://localhost:5501` (unchanged) | Session sync (websocket) |
| tg-fetcher `:5510` | none | Never published |

What the server has today (checked read-only): no nginx and no Caddy binary;
Docker with the `caddy:latest` image already pulled (the `~/subimusic-proxy`
Caddy is not running); port 8090 free; `subi` in the `docker` group; `/opt`
owned by root.

## How the web app signs in (no password stored)

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
  your server) without use. Sign out forgets it and reloads the page.

## How new versions reach people (no self-updater on the web)

The web build has no updater and no update banner: the page is the app.

- Every build's `flutter_bootstrap.js` carries the build's hash. On load (after
  15 s), on focus and every 30 minutes the page re-fetches it past every cache.
  A different hash shows a quiet "New version available · Reload" pill (with
  "Later"). A tab that is hidden and not playing reloads by itself; music is
  never cut off for an update.
- The service worker is registered as `sw.js?v=<hash>`: each build gets its own
  cache and the old caches are deleted, and app code is network first, so it
  never pins an old build.
- Caddy serves `index.html`, `flutter_bootstrap.js`, `flutter.js`,
  `flutter_service_worker.js`, `sw.js`, `version.json`, `manifest.json` and
  `main.dart.js|mjs|wasm` with `Cache-Control: no-cache` (revalidated with ETag,
  a 304 when unchanged). Flutter's output has no content-hashed file names (the
  engine, fonts and icons keep the same URL across builds), so nothing is
  marked immutable: `canvaskit/`, `assets/`, `icons/`, `sqlite3.wasm`,
  `drift_worker.js` get one day, and the service worker re-fetches them for
  each new build.

## Step 1: shuffle server patch (`export/web-server-v1`)

The shuffle server passed the JWT to Navidrome as `t=`, which Navidrome rejects,
so People / friend activity and Smart Shuffle of a playlist failed for web
users. The package sends `jwt=` instead. From the repo checkout on your PC:

```bash
scp -r export/web-server-v1 subi@100.99.105.51:~/web-server-v1
```

```bash
ssh subi@100.99.105.51 'bash ~/web-server-v1/install.sh'
```

It tests on a scratch copy, backs up `navivibe/navidrome.py` to
`/opt/shuffle-server/backups/web-server-v1-<time>/`, patches, runs the new
`test_web_auth.py` plus the security and social suites on the live tree (and
puts the old file back if anything fails), and checks the CORS list. Then on the
server:

```bash
sudo systemctl restart navivibe
```

CORS: both servers read `NAVIVIBE_CORS_ORIGINS`. Unset, the default already
includes `https://subimusic.me`, and your `.env` does not set it, so nothing to
do. If you ever set it, keep `https://subimusic.me` in the list.

## Step 2: the static server (Caddy in Docker, loopback only)

Files: `tool/web/server/` in the repo (`deploy-web.sh`, `Caddyfile`,
`compose.yaml`). Copy them to the server once:

```bash
scp -r tool/web/server subi@100.99.105.51:~/navivibe-web-deploy
```

On the server, create the folder once (the only sudo in this step):

```bash
sudo install -d -o subi -g subi /opt/navivibe-web
```

Deploy the newest release's web zip (GitHub releases from `main` carry
`navivibe-web-<version>+<build>.zip`). The first run also installs the
Caddyfile and compose file into `/opt/navivibe-web`:

```bash
bash ~/navivibe-web-deploy/deploy-web.sh
```

Other forms: `--tag v1.0.0+130`, a zip path, or a `build/web` folder copied from
your PC (`flutter build web --release --wasm --no-web-resources-cdn`), and
`--rollback`. Releases live in `/opt/navivibe-web/releases/<time>_<version>`;
`current` is a symlink replaced with an atomic rename, and the newest 3 are kept.

Check the config and start Caddy once:

```bash
cd /opt/navivibe-web && docker compose run --rm navivibe-web caddy validate --config /etc/caddy/Caddyfile
```

```bash
cd /opt/navivibe-web && docker compose up -d
```

```bash
curl -sI http://127.0.0.1:8090/ | head -5; curl -s 'http://127.0.0.1:8090/rest/ping.view?f=json' | head -c 160; echo
```

The second command should print Navidrome's "missing parameter" JSON (the API
proxy works). Later deploys are just `deploy-web.sh`; no restart. If a deploy
says the Caddy config changed, run `cd /opt/navivibe-web && docker compose up -d --force-recreate`.

What the Caddyfile does:

- Binds `127.0.0.1:8090` only; TLS is Cloudflare's. `admin off`.
- Same-origin Navidrome for `/rest`, `/auth`, `/api`, `/share`. The Navidrome
  admin UI (`/app`) is not proxied here.
- Unknown paths fall back to `index.html` (single-page app).
- Cache headers as described above.
- `X-Content-Type-Options`, `Referrer-Policy: same-origin`, `X-Frame-Options: DENY`,
  HSTS, a `Permissions-Policy`, and this CSP:
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
  Builds use `--no-web-resources-cdn`, so CanvasKit comes from your host. The
  index.html has no inline script, so `script-src` needs no hashes. A server
  address other than these hosts typed into the sign-in screen is blocked, by
  design.
- Access logs replace `t`, `s`, `p`, `jwt` and `token` in query strings with
  `REDACTED`.
- No COOP/COEP: the wasm renderer runs single-threaded without them.

## Step 3: the tunnel (on the server)

Back up the config the service uses, then edit it:

```bash
sudo cp -a /etc/cloudflared/config.yml /etc/cloudflared/config.yml.bak-$(date +%Y%m%d-%H%M%S)
```

```bash
sudoedit /etc/cloudflared/config.yml
```

Change the existing `subimusic.me` entry's `service` and add `navidrome.subimusic.me`
directly below it (keep `session.`, `shuffle.`, `music.`, `api.` and the final
`http_status:404` as they are):

```yaml
  - hostname: subimusic.me
    service: http://127.0.0.1:8090
    originRequest:
      connectTimeout: 60s
      tcpKeepAlive: 30s
      keepAliveConnections: 100
      keepAliveTimeout: 120s
      http2Origin: false
      disableChunkedEncoding: false
  - hostname: navidrome.subimusic.me
    service: http://localhost:4533
    originRequest:
      connectTimeout: 60s
      keepAliveTimeout: 120s
```

Check, add the DNS record for the new name, and restart:

```bash
sudo cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate
```

```bash
sudo cloudflared --config /etc/cloudflared/config.yml tunnel ingress rule https://subimusic.me/
```

```bash
sudo cloudflared tunnel route dns 18d9f431-8f29-4797-8dc9-1ca777e0b137 navidrome.subimusic.me
```

```bash
sudo systemctl restart cloudflared
```

(The second command should print the 127.0.0.1:8090 rule. If `route dns` asks
for a login, add `navidrome` as a proxied CNAME to
`18d9f431-8f29-4797-8dc9-1ca777e0b137.cfargotunnel.com` in the Cloudflare DNS
tab instead.) `~/.cloudflared/config.yml` is an older copy the service does not
use; leave it.

Rollback: restore the `.bak` file and restart `cloudflared`.

## Step 4: Cloudflare dashboard

### Navidrome CORS Transform Rule (navidrome.subimusic.me)

The web app talks to Navidrome on its own origin (`subimusic.me/rest`), so it
needs no CORS. Navidrome 0.64 also already answers cross-origin requests
(`Access-Control-Allow-Origin: *` on `/rest` and `/auth/login`, preflights
included; checked on the server). Add this rule to pin the origin instead of
`*`, or if a future Navidrome stops sending the headers:

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

### Keep admin paths private

- **Navidrome admin UI**: Zero Trust > Access > Applications > Self-hosted,
  domain `navidrome.subimusic.me`, path `app` (and `app/*`), policy "Allow: your
  email". Leave `/rest`, `/auth`, `/api`, `/share` open.
- **Shuffle server `/admin/*`, `/metrics`**: Security > WAF > Custom rules, Block
  when `http.host eq "shuffle.subimusic.me" and (starts_with(http.request.uri.path, "/admin") or http.request.uri.path eq "/metrics")`.
  Use Tailscale (`100.99.105.51:5500`) for admin work.
- **tg-fetcher**: no hostname, ever.

### Rate limits for a public sign-in page (recommended)

Security > WAF > Rate limiting rules: `/auth/login` POST on `subimusic.me` and
`navidrome.subimusic.me`, 10 per minute per IP, block 10 minutes;
`shuffle.subimusic.me` `/social/jam/join`, 6 per minute per IP.

### Edge caching

The Caddy headers decide. If you add a Cache Rule, bypass cache for `/rest/*`,
`/auth/*`, `/api/*`, `/share/*`, `index.html`, `flutter_bootstrap.js` and `sw.js`.

## Step 5: check it

1. `https://subimusic.me` on a computer: the desktop UI. Narrow the window below
   ~760 px: the phone UI. On an Android phone: the phone UI.
2. Sign in, play a song, lock the phone: the lock screen shows title, artist,
   cover and play/pause/next (Media Session). Keyboard media keys work on a
   computer.
3. Jam: start one in the browser, join it from the Android app with the code.
4. Deploy a newer build while a tab is open, then focus the tab: "New version
   available · Reload" appears.
5. Android Chrome menu > Install app: it opens in its own black window.
6. An existing Android/Windows install still signs in with `https://subimusic.me`.

## Updating later

On `main`, CI attaches `navivibe-web-<version>+<build>.zip` to the release.
Then on the server:

```bash
bash ~/navivibe-web-deploy/deploy-web.sh
```

Open tabs pick it up through the Reload prompt; idle ones reload by themselves.

## What the web app does not do

Hidden in the browser build: downloads and the Downloaded list, local music
folders, the download location, CSV export, song recognition, the self-updater
and its banner, "Sign in another device", tray, global hotkey, mini-player
window, window controls, Windows SMTC (Media Session replaces it). Sharing
shares the link and caption; the PNG card is app-only.

Background audio on Android Chrome works while the page plays, but a battery
manager can still stop a backgrounded tab; the native app remains the better
Android client. The first play after opening the page needs a tap (browser
autoplay rules).
