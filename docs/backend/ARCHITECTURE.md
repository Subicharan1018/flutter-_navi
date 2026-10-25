# Backend architecture

```
 phone / desktop app                          web player
        │  HTTPS                                   │
        ▼                                          ▼
   Cloudflare edge  (WAF, rate limits, TLS) ── fail2ban bans land here
        │  QUIC tunnel
        ▼
   cloudflared  (this machine; connects to 127.0.0.1)
        ├── music.example.org   ─▶ Navidrome            :4533   library, streaming, accounts
        ├── shuffle.example.org ─▶ navivibe (waitress)  :5500   recommendations, history, lyrics,
        │                                                       recognise, social, /fetch proxy
        └── session.example.org ─▶ navivibe-session     :5501   live playback sync (websocket)
                                         │
 navivibe :5500 ──signed HTTP──▶ tg-fetcher (FastAPI) 127.0.0.1:5510 ──Telegram──▶ music bot
                                         │
                                         └─ downloads FLAC ─▶ staging ─▶ library folder ─▶ Navidrome scans it
```

Only Navidrome, the shuffle server and the session service are published. tg-fetcher is never
reachable from outside; the shuffle server is its only caller.

## Components

| Component | Process | Port | Code | Role |
|---|---|---|---|---|
| Navidrome | docker | 4533 | (upstream) | Music library, streaming, **user accounts** (the identity provider). |
| Shuffle server | `navivibe.service`: `server.py` under waitress, 16 threads, **one process** | 5500 | `navivibe/` | `/next` queues, feedback, stats and Replay, Flow, weekly mix, lyrics search and translation, song recognition, `/intent`, social (Jam, collaborative playlists, Blend, friend activity), `/me/capabilities`, the `/fetch/*` proxy. One process on purpose: the recommender keeps live per-user state in memory. |
| Session sync | `navivibe-session.service`: uvicorn `navivibe.session:app` | 5501 | `navivibe/session.py` | One room per user; devices on the same account share and hand over playback. REST `/playback/state` + websocket `/ws/session`. |
| tg-fetcher | `tg-fetcher.service`: `python -m tgfetch.main` | 5510 (loopback) | `tgfetch/` | Telegram client + job worker + internal API. Search the bot, rank candidates, download, tag, move into the library, trigger/await the Navidrome scan; also builds the daily trending charts. |
| Background jobs | threads inside the shuffle server (`scheduler.py`) | — | `navivibe/scheduler.py` | Nightly play import from Navidrome, model retrain, catalog pipeline poll, weekly mix. |
| Timers | `navivibe-backup.timer`, `navivibe-healthcheck.timer` | — | `navivibe/deploy/` | Nightly SQLite backups; 5-minute health check with optional phone alert. |

## Request path

1. The app sends `Authorization: Basic base64(user:password)` (or a Navidrome JWT) on every call.
2. `before_request`: real client IP (`CF-Connecting-IP`, trusted only from loopback), body-size cap, per-IP bucket.
3. `require_auth`: credential cache → otherwise Navidrome `ping` → user name (validated) → per-user bucket → `g.username`.
4. The route handler reads only data keyed by `g.username` (plus opt-in shared social state).
5. For `/fetch/*`: `fetch_access.has_access(user)`, then a call to tg-fetcher signed with
   HMAC(timestamp, user, grant, method, path). tg-fetcher verifies and acts for that user.

## Data files

Paths are the defaults; every one has an environment variable (see `.env.example`).

| File | Owner | Contents | Backed up |
|---|---|---|---|
| `/opt/shuffle-server/.env` | shuffle server | settings and secrets (mode 600) | yes, in `models.tar.gz` (mode-protect the backup dir) |
| `/DATA/AppData/navivibe/listening_logs/<user>_listening_log.db` | shuffle server | one SQLite per user: plays, skips, impressions | nightly |
| `/DATA/AppData/navivibe/social.db` | shuffle server | opt-in profiles, collaborative playlists, Blends, **`fetch_access` grants** | add to backup |
| `/opt/shuffle-server/catalog.db` | catalog pipeline | per-song metadata, language, mood, audio features | nightly |
| `/opt/shuffle-server/models/v3/`, `model_state_<user>.json` | trainer | recommender artifacts | nightly |
| `/opt/shuffle-server/lyrics.db` | lyrics tools | lyrics search index and translations cache | rebuildable |
| `/opt/shuffle-server/id_map.json` | id migration | old → new Navidrome song ids after a Navidrome upgrade | small |
| Jams | memory only | live state; gone on restart by design | — |
| `/opt/tg-fetcher/.env` | tg-fetcher | Telegram API credentials, the two shared secrets, LLM key | yes |
| `/opt/tg-fetcher/session/tg.session` | tg-fetcher | **the logged-in Telegram account** (mode 600) | yes, restrict access |
| `/opt/tg-fetcher/data/fetch.db` | tg-fetcher | searches, candidates, jobs, batches, trending charts | nightly |
| `/opt/tg-fetcher/data/billboard/` | tg-fetcher | cached chart pages | rebuildable |
| `/DATA/Media/.tg-staging/` | tg-fetcher | downloads in progress | no |
| `/DATA/Media/Music/tg-fetcher/` | tg-fetcher | finished files (Navidrome's library) | with the library |

Nothing here ever holds a user's Navidrome password.

## Code map (shuffle server)

| Module | Job |
|---|---|
| `server.py` | Flask app, auth, routes for queue/feedback/stats/health/metrics/admin |
| `hardening.py` | credential cache, rate limiter, failed-login lockout, security headers, client IP, metrics |
| `fetch_proxy.py`, `fetch_access.py`, `fetch_signing.py`, `bin/fetch-access` | download gating and the signed bridge to tg-fetcher |
| `session.py` | live playback sync service |
| `social.py` → `friends.py`, `jam.py`, `collab.py`, `blend.py`, `social_db.py` | social features |
| `model.py`, `recsys/`, `flow.py`, `discover.py`, `weekly_mix.py`, `intent.py`, `ai_order.py` | recommendation |
| `catalog/` | song metadata pipeline (Navidrome → `catalog.db`) |
| `lyrics_tools.py`, `recognize.py` | lyrics search/translation, song recognition (AcoustID) |
| `stats.py`, `month_stats.py`, `feedback.py`, `listener_memory.py` | listening history and reports |
| `scheduler.py`, `preprocess.py`, `sync_navidrome.py` | background jobs |

tg-fetcher: `api.py` (HTTP), `signing.py` (request verification), `worker.py` (jobs), `sources/` (the
Telegram bot), `rank.py`/`library.py` (matching), `importer.py` (tagging and moving files), `links.py`
(playlist links), `trending.py`/`billboard.py` (charts), `db.py`, `config.py`.
