# Backend security

Scope: the shuffle server (`navivibe/`, ports 5500 and 5501) and tg-fetcher (`:5510`) for a
small, private community (about a dozen people who each have a Navidrome account), reached
through a Cloudflare Tunnel.

## Threat model

| Who / what | What they might try | What stops it |
|---|---|---|
| Anyone on the internet | Guess passwords; scan routes; flood the server | Navidrome login is the only credential; failed-login lockout; per-IP and per-user rate limits; fail2ban at the edge; every route but `/health`, `/ready`, `/weather`, `/` needs a login, and those four say almost nothing |
| A signed-in user | Read or change another person's data; use admin routes; download without permission | The user name comes only from the validated login; every query is keyed by it; Jam / collab / Blend need membership; `/admin/*` needs `NAVIVIBE_ADMIN_USERS`; downloads need an explicit grant |
| A signed-in user | Burn money or CPU (LLM calls, audio fingerprinting, Telegram) | Stricter buckets on `/intent`, `/lyrics/translate`, `/recognize`, `/fetch` writes, Jam join; request body caps; tg-fetcher daily limits |
| Someone who reads the public code | Find a hole in the code, or a secret in it | No secrets in the repo or its history (see "Publishing the code"); every secret lives in `.env` |
| Something else on the server or LAN | Call tg-fetcher pretending to be a user | tg-fetcher binds `127.0.0.1` and refuses any call not signed with the shared HMAC secret |
| A stolen backup or disk | Read `.env`, the Telegram session | Backups and `.env` are mode 600/700; the Telegram session is a secondary account you can revoke |

Not defended: someone with shell access as the service user (they own the secrets); a
compromised Navidrome (it is the identity provider); Cloudflare itself.

## Access control

**Identity.** Every protected request carries the user's Navidrome login (HTTP Basic or a
Navidrome JWT). The server validates it against Navidrome (cached for 5 minutes, hashed in
memory) and sets the user name for that request. User names are checked against
`[\w .@+-]{1,64}` (no leading dot, no slashes) *before* they are used, because they become file
names (`<user>_listening_log.db`). If Navidrome is down the answer is `503`, never a "wrong
password", so an outage cannot lock anyone out.

**Admins.** `NAVIVIBE_ADMIN_USERS` (comma-separated). They see `/admin/users` and always may download.

**Per-user isolation.** Listening logs and model state are per-user files. Social features are
opt-in per person (`/social/settings`); Jam needs the 6-character code *and* membership for every
action; collaborative playlists and Blends check membership/ownership in every handler
(`navivibe/tests/test_security.py::test_collab_and_blend_are_private_to_their_members`,
`::test_outsiders_cannot_read_or_change_a_jam`); the session service keeps one room per user and
`/playback/state` only ever returns the caller's own.

**Downloads need an explicit grant.** Search online, labels, playlist links, batches and
recognise-and-download all go through `/fetch/*`. They are allowed only for

1. admins, or
2. users granted with `navivibe/bin/fetch-access grant <user>` (table `fetch_access` in `social.db`), or
3. everyone, if you set `FETCH_DEFAULT_ACCESS=all` (default `none`) and they were not revoked.

It is enforced twice:

- **Shuffle server** (`navivibe/fetch_proxy.py`): a user without access gets `403` and tg-fetcher is
  never called. `GET /me/capabilities` returns `{"download": bool}`; the app shows download screens
  only when `!kPublicBuild && download`. The old `GET /fetch/enabled` still works for older apps.
- **tg-fetcher** (`tgfetch/signing.py`): every request must carry `X-Internal-Token` *and* an HMAC-SHA256
  signature (`INTERNAL_HMAC_SECRET`) over timestamp, user, the grant flag, method and path, valid
  for 60 seconds. A leaked token alone, a replayed request, or a request to a different route
  does not verify, and nobody can claim a grant the shuffle server did not sign. The service
  refuses to start without the secret.

The daily trending charts are public data and stay visible to every signed-in user
(`FETCH_TRENDING_OPEN=0` to close them too); downloading from them is still gated.

**Input validation.** All ids in paths are typed (`<int:...>`); candidate/search ids are cast to
integers; at most 100 picks per batch; playlist ids match `[A-Za-z0-9_-]{1,64}`; chart names
`[a-z0-9_]{1,32}`; only `limit` is forwarded as a query parameter. **SSRF:** the shuffle server only
ever connects to fixed hosts (Navidrome, tg-fetcher, the LLM and AcoustID endpoints from `.env`); a
pasted playlist link is parsed in tg-fetcher (`links.py`) and only `deezer.com` / `open.spotify.com`
playlist URLs with numeric/alphanumeric ids are fetched — the user never supplies a URL that is
requested directly. **Path traversal:** no route takes a file path; files are chosen by the server
from the validated user name.

**CORS.** Only the origins in `NAVIVIBE_CORS_ORIGINS` (default: the author's own web player),
no credentials, limited headers. Native apps do not use CORS.

## Rate limits

Token buckets in memory (no extra service), per client IP *and* per user. Real client IP comes
from `CF-Connecting-IP`, trusted only when the request arrives from loopback (cloudflared); a
malformed value is ignored. Over the limit: `429` with `Retry-After`.

| Class | Routes | Burst / per minute (per user) |
|---|---|---|
| `next` | `/next` | 20 / 40 |
| `feedback` | `/feedback*` | 60 / 240 |
| `fetch` | `/fetch/*` reads (status polling) | 60 / 90 |
| `fetch_write` | `/fetch/*` POST/DELETE | 12 / 12 |
| `lyrics` | `/search/lyrics` | 40 / 60 |
| `translate` | `/lyrics/translate` (paid LLM) | 6 / 8 |
| `llm` | `/intent` (paid LLM) | 6 / 10 |
| `recognize` | `/recognize` (upload + AcoustID) | 6 / 4 |
| `jam_join` | `/social/jam/join` | 6 / 6 |
| `social` | other `/social/*` | 120 / 180 |
| `default` | everything else | 60 / 120 |
| `ip` | any route, per IP | 300 / 600 |
| `ip_strict` | the costly classes, per IP (households share it) | 60 / 60 |
| `ip_public` | `/health /ready /weather /` per IP | 120 / 60 |
| `ws_connect`, `ws_msg` | session websocket: handshakes per IP, messages per device | 30 / 60, 60 / 1200 |

Tune any class with `NAVIVIBE_RL_<CLASS>=<burst>/<per-minute>` in `.env` (for example
`NAVIVIBE_RL_RECOGNIZE=3/2`); a malformed value is ignored. **Failed logins:** 10 in 5 minutes from
one IP lock that IP out for 15 minutes (`NAVIVIBE_AUTH_FAIL_MAX/WINDOW/LOCKOUT`); only failures are
charged, so a household sharing an IP is unaffected. The session service has the same lockout.

**Jam codes** are 6 symbols from 32 (about a billion), generated with the OS random source. Joining
is limited by the `jam_join` bucket, plus 8 wrong codes per 15 minutes per user, so brute-forcing a
live code is not practical.

**Body limits.** Global 512 KB; `/recognize` 7 MB (6 MB of audio); `/lyrics/translate` 256 KB;
`/fetch` 16 KB; `/intent` 4 KB; `/social` 64 KB. Waitress refuses anything over 8 MB before it is
buffered, and the session websocket caps a message at 1 MiB.

**Exposure.** `/metrics` answers only to localhost without a `CF-Connecting-IP` header, or to a
caller sending `X-Metrics-Token: <NAVIVIBE_METRICS_TOKEN>`. `/health` returns `{"status":"ok"}`, and
`/ready` `{"ready":bool}`, to everyone else; engine state, versions and per-check detail are for
localhost or the token. Security headers on every response: `nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: no-referrer`, a `default-src 'none'` CSP, HSTS, `Cache-Control: no-store`.

## fail2ban

See [`deploy/fail2ban/README.md`](../../deploy/fail2ban/README.md) in the backend repo. Two jails
read the `AUTH_FAIL` and `AUTH_LOCKOUT` journal lines; because every request arrives from
`cloudflared` on loopback, bans are applied **at Cloudflare's edge** through the API (an IP Access
Rule), not with a local firewall. Without a Cloudflare token the in-server lockout still works.

## Cloudflare edge rules

Set once in the dashboard (they cannot live in `config.yml`): a rate-limiting rule for the Navidrome
login (`/auth/login`, `/rest/ping`), a looser one for `shuffle.` / `session.` hosts, Bot Fight Mode
**off** (it breaks the apps), Always Use HTTPS, Minimum TLS 1.2. The details are in
`deploy/OPERATIONS.md` ("Cloudflare dashboard").

## Key rotation

Do these one at a time; each is a `.env` edit plus a restart (`sudo systemctl restart …`).

| Secret | Where | Rotate |
|---|---|---|
| Navidrome password (any user) | Navidrome | Change it there; the shuffle server picks it up when the cache expires (5 min). |
| `TG_FETCHER_TOKEN` = `INTERNAL_TOKEN` | both `.env` | `openssl rand -hex 32`, write in both files, restart `tg-fetcher` then `navivibe`. |
| `TG_FETCHER_HMAC_SECRET` = `INTERNAL_HMAC_SECRET` | both `.env` | Same. Until both restarted, downloads answer "offline"; nothing else is affected. |
| `NAVIVIBE_METRICS_TOKEN` | `.env` | New value, restart `navivibe`, update the scraper. |
| `GROQ_API_KEY`, `LLM_API_KEY`, `ACOUSTID_API_KEY`, `LASTFM_API_KEY` | `.env` | Create a new key at the provider, replace, restart, delete the old key at the provider. |
| Cloudflare API token (fail2ban) | `/etc/fail2ban/cloudflare.env` | Roll the token in the Cloudflare dashboard, edit the file, `fail2ban-client reload`. |
| Cloudflare tunnel credentials | `/etc/cloudflared/*.json` | `cloudflared tunnel token` / re-create the tunnel; restart `cloudflared`. |
| Telegram session | `/opt/tg-fetcher/session/` | Telegram → Settings → Devices → terminate the session, then `venv/bin/python -m spike.login` again. If `TG_API_HASH` leaked, regenerate it at my.telegram.org. |

If a secret was ever in git history, rotating is not optional: removing it from the latest commit
does not remove it from the history.

## Publishing the code

The backend repos are meant to be published as **fresh repositories with no history** (one commit),
with `.env`, `data/`, the Telegram `session/`, databases, models and logs excluded. The old git
history contained an admin password, so never push it. Before every push, scan:

```bash
grep -rniE 'gsk_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30}|BEGIN [A-Z ]*PRIVATE KEY' .
grep -rniE '(password|passwd|api_key|apikey|secret|token)[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{20,}' .
```

`.env.example` holds only `<placeholders>`.

## What to do if something leaks

1. Rotate that secret (table above). 2. Look for abuse: `journalctl -u navivibe -g 'AUTH_FAIL|AUTH_LOCKOUT'`,
`fail2ban-client status`, `venv/bin/python navivibe/bin/fetch-access list`. 3. If the Telegram session leaked,
terminate it in Telegram first.
