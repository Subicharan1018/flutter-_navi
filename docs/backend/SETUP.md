# Backend setup

How to run the two NaviVibe backends on your own server:

- **navivibe-backend** (the *shuffle server*): recommendations, listening history, lyrics, song
  recognition, Jam and the other social features, and the proxy the app uses for downloads.
  Flask on waitress (`:5500`), plus a live playback-sync service (`:5501`).
- **tg-fetcher**: the downloader. FastAPI on `127.0.0.1:5510`; fetches songs through a Telegram
  bot and drops them in the Navidrome library. Only the shuffle server may call it.

Neither stores passwords. Users sign in with their **Navidrome** account; the shuffle server
checks the login against Navidrome. Read [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit
and [SECURITY.md](SECURITY.md) before exposing anything to the internet.

## 0. What you need

| Need | Notes |
|---|---|
| A Linux box with Python 3.12 | Tested on Ubuntu 24.04. `ffmpeg` (with the chromaprint muxer, as Ubuntu's has) for song recognition; `sqlite3` for the backup script. |
| [Navidrome](https://www.navidrome.org) | Already running, with your music and users. The backends talk to it on `http://localhost:4533`. |
| A way in from the internet | The author uses a Cloudflare Tunnel (`cloudflared`). Any reverse proxy works. |
| Optional keys | Groq (lyrics translation, "say what you want" mixes, mood tags), AcoustID (song recognition), Last.fm. Each feature is off without its key. |
| Optional, for downloads | A secondary Telegram account and API credentials from <https://my.telegram.org>. |

## 1. Shuffle server

```bash
sudo mkdir -p /opt/shuffle-server && sudo chown $USER: /opt/shuffle-server
git clone <your navivibe-backend repo> /opt/shuffle-server/navivibe
cd /opt/shuffle-server
python3 -m venv venv
venv/bin/pip install -r navivibe/requirements.txt
```

The code is the Python package `navivibe`, so the folder that *contains* it
(`/opt/shuffle-server`) must be on `PYTHONPATH`; the systemd units set that.

**Settings.** Everything is environment variables, read from `/opt/shuffle-server/.env`:

```bash
cp navivibe/.env.example .env && chmod 600 .env
$EDITOR .env
```

`.env.example` lists every variable the code reads, with defaults and comments. The ones to
set on day one:

- `GROQ_API_KEY`, `ACOUSTID_API_KEY` (optional features, see above);
- `NAVIVIBE_METRICS_TOKEN` if you want to scrape `/metrics` from another machine;
- `TG_FETCHER_TOKEN` and `TG_FETCHER_HMAC_SECRET` if you run the downloader (section 2).

Generate secrets with `openssl rand -hex 32`. Never commit `.env`.

**Navidrome connection.** `NAVIDROME_URL` (default `http://localhost:4533`) is where logins are
checked. `NAVIDROME_DB` / `NAVIDROME_DB_URI` point at Navidrome's SQLite file (read-only) for the
lyrics index and for matching a recognised song to your library. Name your Navidrome admin(s) in
`NAVIVIBE_ADMIN_USERS` (default `admin`; the unit file sets it).

**Library data.** Build the catalog and the first models once (takes a while on a big library):

```bash
cd /opt/shuffle-server
PYTHONPATH=. venv/bin/python navivibe/preprocess.py --full
PYTHONPATH=. venv/bin/python -m navivibe.catalog.pipeline          # reads Navidrome, writes catalog.db
PYTHONPATH=. venv/bin/python -m navivibe.recsys.train              # trains the v3 recommender
```

**Run it as services** (needs sudo):

```bash
sudo cp navivibe/deploy/systemd/navivibe.service navivibe/deploy/systemd/navivibe-session.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now navivibe navivibe-session
curl -s http://127.0.0.1:5500/ready          # {"ready":true,"checks":{...}} once models have loaded
curl -s http://127.0.0.1:5501/health         # {"status":"ok"}
```

`navivibe/deploy/install.sh` does the same plus the nightly backup and health-check timers
(`navivibe-backup.timer`, `navivibe-healthcheck.timer`); read it before running it, it also edits
Navidrome's config.

**Ports.** `5500` shuffle server, `5501` session sync: both bind `127.0.0.1` only. The reverse
proxy is the only way in.

**Reverse proxy.** With a Cloudflare Tunnel copy `navivibe/deploy/cloudflared/config.yml.example`
to `/etc/cloudflared/config.yml`, fill in your tunnel ID and hostnames, restart `cloudflared`.
Optional nginx rules are in `deploy/nginx/`.

## 2. tg-fetcher (downloads) — optional

Skip this and the app simply has no download features.

```bash
sudo mkdir -p /opt/tg-fetcher && sudo chown $USER: /opt/tg-fetcher
git clone <your tg-fetcher repo> /opt/tg-fetcher
cd /opt/tg-fetcher
python3 -m venv venv
venv/bin/pip install -r requirements.txt
cp .env.example .env && chmod 600 .env
$EDITOR .env
```

Fill in `TG_API_ID`, `TG_API_HASH` (from <https://my.telegram.org> → API development tools),
`TG_SOURCE` (the `@username` of the Telegram music bot you search with), and two fresh secrets:

```bash
echo "INTERNAL_TOKEN=$(openssl rand -hex 32)"
echo "INTERNAL_HMAC_SECRET=$(openssl rand -hex 32)"
```

Put **the same two values** in `/opt/shuffle-server/.env` as `TG_FETCHER_TOKEN` and
`TG_FETCHER_HMAC_SECRET`. Without them the service refuses to start and the shuffle server
reports downloads as unavailable.

**Create the Telegram session** (once, interactively; use a *secondary* Telegram account, because
automating a personal account can get it limited):

```bash
cd /opt/tg-fetcher
venv/bin/python -m spike.login        # asks for the phone number, the code Telegram sends, and the 2FA password
```

It writes `session/tg.session` (mode 600). That file *is* the logged-in account: never copy it
into git, backups you share, or chat.

**Check your library paths**, then install the service:

```bash
# in .env: LIBRARY_DIR (Navidrome's music folder), STAGING_DIR (same disk), NAVIDROME_DB (read-only)
sudo cp deploy/tg-fetcher.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now tg-fetcher
curl -s 127.0.0.1:5510/health          # {"status":"ok","telegram":true,"worker":true,...}
```

### Who may download

New users get **no** downloads. Admins (`NAVIVIBE_ADMIN_USERS`) always can. Everyone else needs a
grant on the shuffle server:

```bash
cd /opt/shuffle-server
venv/bin/python navivibe/bin/fetch-access list
venv/bin/python navivibe/bin/fetch-access grant alice
venv/bin/python navivibe/bin/fetch-access revoke alice
```

Takes effect within about five seconds, no restart. `FETCH_DEFAULT_ACCESS=all` flips the default
to "everyone unless revoked". The app asks `GET /me/capabilities` and shows the download screens
only to people who may use them (and never in a public build).

## 3. First run

1. `curl -u <navidrome-user>:<password> http://127.0.0.1:5500/model/status` returns JSON (a wrong password returns 401).
2. Sign in from the app with your Navidrome server URL and account. The first queue may be generic; it learns as you listen.
3. `journalctl -u navivibe -f` shows requests slower than a second, every 5xx, and failed sign-ins (`AUTH_FAIL`).
4. With downloads on: sign in as an admin, open Search Online, search a song. As a user without a grant the screens are hidden, and `curl` against `/fetch/jobs` answers 403.

## 4. Tests

Run them in a scratch copy, not in the live folder:

```bash
rm -rf /tmp/nv && mkdir -p /tmp/nv && cp -r /opt/shuffle-server/navivibe /tmp/nv/navivibe
cd /tmp/nv && PYTHONPATH=/tmp/nv /opt/shuffle-server/venv/bin/python -m pytest navivibe/tests -q

rm -rf /tmp/tgf && cp -r /opt/tg-fetcher /tmp/tgf && rm -rf /tmp/tgf/session /tmp/tgf/data /tmp/tgf/.env
cd /tmp/tgf && /opt/tg-fetcher/venv/bin/python -m pytest -q
```

No test touches Navidrome, Telegram or the network; the Telegram session is not needed.

## 5. Updating

Pull, run the tests as above, then `sudo systemctl restart navivibe navivibe-session tg-fetcher`.
`navivibe/deploy/rollback.sh` restores the previous units. Rotate keys with the steps in
[SECURITY.md](SECURITY.md#key-rotation).
