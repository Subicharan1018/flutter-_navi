# preview-feed-v1

**Swipe to fetch** (item 3 of `docs/feature-scout-research.md`): a vertical feed of 30 s previews of songs that are **not** in the
library. The app swipes through them; a heart means "fetch it", a swipe past means "no". Both are stored as an explicit yes/no
signal. Built on the live code read on 24 Nov 2026. Needs weekly-exploration-v1 (the `server.py` anchor) and exportify-v1 before it.

## What it does
* `GET /preview-feed?limit=N` (default 12, max 30): songs with a playable preview, each `{key, title, artist, album, art_url,
  preview_url, provider, duration_s: 30, source, reason, expires_at}`, plus `remaining` / `cap` (today's hearts).
* `POST /preview-feed/signal` `{key, title, artist, verdict: yes|no, ratio, album?, art_url?, source?}`: `yes` (heart) counts against
  the daily cap and answers **429** with `remaining: 0` when it is used up; `no` (skipped) is free. The key must be the one the server
  derives from title + artist (a forged key is a 400). A heart is never taken back by the swipe that follows it the same day.
* Same gate as `/fetch`: signed in **and** download access (`fetch_access.has_access`), else **403** and nothing is read or called.
  The app never talks to tg-fetcher; the heart only unlocks the app's ordinary `/fetch` search -> download path, which carries the
  grant and the HMAC bridge as always, so the per-user limits of tg-fetcher still apply on top of the feed's own daily cap.

## Where songs come from (each dropped if the library has it, or the listener already decided on it)
| Source | What |
|---|---|
| `chart` | the newest snapshot of every trending chart in tg-fetcher's `fetch.db` (**read-only**), best rank first, rows tg-fetcher already links to the library left out |
| `release` | Deezer's new releases (`/editorial/0/releases` + the first tracks of 6 albums), cached 6 h |
| `friend` | what other listeners on this server hearted in the feed in the last 30 days (no names in the answer) |

"In the library" = same ISRC, or same clean title + first artist as a row in `catalog.db` (read-only). Names are compared with
combining marks kept, so Tamil/Hindi titles are never cut into pieces.

## Previews
Deezer `preview` (`/track/<id>`, works from India where search does not) first, then iTunes `previewUrl` (search, IN storefront, title
and artist must match). **Only the URL is kept**, for 6 h (a miss for 1 h), and expired rows are purged on every feed build; the
audio is never fetched or stored here, the phone streams it from the provider's CDN. One feed request makes at most 14 outside
calls; a provider that is down just yields fewer songs.

## Daily cap
`PREVIEW_FEED_DAILY_CAP` (default 25 hearts per listener per India day; set it in `/opt/shuffle-server/.env`).

## The recommender signal
`signals(user, key, verdict, title, artist, album, art_url, source, ratio, ts, day)` in `preview_feed.db` is the authoritative record.
The app also reports the same yes/no through the normal play-event outbox (`POST /feedback`, `play_source: other`,
`file_path: preview:<key>`), a skip as `skip`, a heart as `complete` (an explicit heart counts as at least half heard).

## Install (owner commands)
```
scp -r tool/server/preview-feed-v1 subi@100.99.105.51:~/
```
On the server (as `subi`, no sudo):
```
cd ~/preview-feed-v1
bash install.sh --check      # scratch tests only, nothing live is touched
bash install.sh              # tests, back up, patch, test again; puts everything back if a test fails
sudo systemctl restart navivibe
```
Order: after the packages in `../INSTALL-ORDER.md` (it only needs weekly-exploration-v1 and fetch_access). Rollback is printed by
`install.sh`.

## Tests
`files/navivibe-tests/test_preview_feed_v1.py` (20 tests: names incl. Tamil, Deezer/iTunes resolution, caching and expiry, budget,
chart/release/friend sources, library and decided filtering, feed order and limit, cap and India-day reset, validation, routes incl.
401/403/429). Repo only: `tests_repo/test_patch.py` (`python -m pytest tool/server/preview-feed-v1/tests_repo`).
